import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.7.1";
import { google } from "npm:googleapis@126.0.0";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Initialize Google Auth
function getGoogleAuth() {
  const email = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_EMAIL');
  const privateKey = Deno.env.get('GOOGLE_PRIVATE_KEY');

  if (!email || !privateKey) {
    throw new Error('Missing Google Service Account credentials in Supabase Secrets.');
  }

  return new google.auth.JWT(
    email,
    null,
    privateKey.replace(/\\n/g, '\n'),
    [
      'https://www.googleapis.com/auth/spreadsheets',
      'https://www.googleapis.com/auth/drive'
    ]
  );
}

function sanitizeSheetTitle(title: string): string {
  // Google Sheets tab names cannot contain: \ / ? * : [ ]
  // Max length is 31 characters
  let clean = title.replace(/[\\\/\?\*\:\[\]]/g, '').trim();
  if (clean.length > 31) {
    clean = clean.substring(0, 31);
  }
  return clean || 'عميل بدون اسم';
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    
    let user = null;
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    if (authHeader) {
      const token = authHeader.replace('Bearer ', '');
      const { data } = await supabaseAdmin.auth.getUser(token);
      user = data?.user;
    }

    const body = await req.json().catch(() => ({}));
    const { action, email, table, record, type } = body;

    // 1. Setup Action (called from Admin UI)
    if (action === 'setup') {
      if (!user) throw new Error('Unauthorized');
      const { data: profile } = await supabaseAdmin.from('profiles').select('role').eq('id', user.id).single();
      if (profile?.role !== 'admin') throw new Error('Only admins can setup backup');

      const auth = getGoogleAuth();
      const drive = google.drive({ version: 'v3', auth });
      const sheets = google.sheets({ version: 'v4', auth });

      // Create Spreadsheet
      const resource = {
        properties: {
          title: 'Ash Pure ERP - Backup',
        },
      };
      
      const spreadsheet = await sheets.spreadsheets.create({
        requestBody: resource,
        fields: 'spreadsheetId,spreadsheetUrl',
      });

      const spreadsheetId = spreadsheet.data.spreadsheetId;

      // Add Sheets for Products, Customers
      await sheets.spreadsheets.batchUpdate({
        spreadsheetId,
        requestBody: {
          requests: [
            { addSheet: { properties: { title: 'المنتجات' } } },
            { addSheet: { properties: { title: 'العملاء' } } },
            { deleteSheet: { sheetId: 0 } } // Delete the default Sheet1
          ]
        }
      });

      // Write headers for default sheets
      await sheets.spreadsheets.values.batchUpdate({
        spreadsheetId,
        requestBody: {
          valueInputOption: 'RAW',
          data: [
            {
              range: 'المنتجات!A1:H1',
              values: [['الاسم', 'SKU', 'الباركود', 'التصنيف', 'المخزون', 'التكلفة', 'سعر البيع بالتجزئة', 'تاريخ الصلاحية']]
            },
            {
              range: 'العملاء!A1:F1',
              values: [['الاسم', 'الهاتف', 'العنوان', 'الفئة', 'الرصيد', 'إجمالي المشتريات']]
            }
          ]
        }
      });

      // Share Spreadsheet with user email
      await drive.permissions.create({
        fileId: spreadsheetId,
        requestBody: {
          type: 'user',
          role: 'writer',
          emailAddress: email,
        },
      });

      // Save spreadsheetId in app_settings table
      await supabaseAdmin.from('app_settings').upsert({ id: 'google_spreadsheet_id', value: spreadsheetId });

      return new Response(JSON.stringify({ 
        success: true, 
        message: 'تم إنشاء الشيت ومشاركته مع البريد الإلكتروني بنجاح!',
        url: spreadsheet.data.spreadsheetUrl
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 2. Sync Action (Triggered by Database Webhook or manually)
    if (table && record) {
      // Get Spreadsheet ID from app_settings
      const { data: setting } = await supabaseAdmin.from('app_settings').select('value').eq('id', 'google_spreadsheet_id').single();
      if (!setting?.value) {
        return new Response(JSON.stringify({ error: 'Spreadsheet not setup yet' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const spreadsheetId = setting.value;
      const auth = getGoogleAuth();
      const sheets = google.sheets({ version: 'v4', auth });

      let sheetName = '';
      let rowValues = [];
      let matchCol = '';
      let matchVal = '';

      if (table === 'products') {
        sheetName = 'المنتجات';
        rowValues = [
          record.name || '',
          record.sku || '',
          record.barcode || '',
          record.category || '',
          record.stock || 0,
          record.cost || 0,
          record.price_retail || 0,
          record.expiry || ''
        ];
        matchCol = 'SKU';
        matchVal = record.sku;
      } else if (table === 'customers') {
        sheetName = 'العملاء';
        rowValues = [
          record.name || '',
          record.phone || '',
          record.address || '',
          record.type || '',
          record.balance || 0,
          record.total_purchases || 0
        ];
        matchCol = 'الهاتف';
        matchVal = record.phone;
      } else if (table === 'invoices') {
        const rawCustomerName = record.customer_name || 'عميل نقدي';
        sheetName = sanitizeSheetTitle(rawCustomerName);
        
        // Wait 2 seconds to make sure invoice_items are inserted by the client
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        // Fetch invoice items
        let itemsSummary = '';
        try {
          const { data: items } = await supabaseAdmin
            .from('invoice_items')
            .select('name, qty')
            .eq('invoice_id', record.id);
          if (items && items.length > 0) {
            itemsSummary = items.map(i => `${i.name} (${i.qty})`).join('، ');
          }
        } catch (err) {
          console.error('Error fetching invoice items:', err);
        }

        const paymentMethods: Record<string, string> = {
          cash: 'كاش 💵',
          deferred: 'آجل 📋',
          bank: 'تحويل بنكي 🏦',
          vodafone: 'فودافون كاش 📱',
          instapay: 'إنستا باي ⚡'
        };
        const paymentMethodLabel = paymentMethods[record.payment_method] || record.payment_method || '';

        rowValues = [
          record.id || '',
          record.date || '',
          itemsSummary,
          record.subtotal || 0,
          record.discount || 0,
          record.tax || 0,
          record.total || 0,
          record.paid || 0,
          record.remaining || 0,
          paymentMethodLabel
        ];
        matchCol = 'رقم الفاتورة';
        matchVal = record.id;
      }

      if (sheetName) {
        // Ensure the sheet exists
        const spreadsheet = await sheets.spreadsheets.get({ spreadsheetId });
        const sheetsList = spreadsheet.data.sheets || [];
        const sheetExists = sheetsList.some(s => s.properties?.title === sheetName);

        if (!sheetExists) {
          // Create the sheet
          await sheets.spreadsheets.batchUpdate({
            spreadsheetId,
            requestBody: {
              requests: [
                { addSheet: { properties: { title: sheetName } } }
              ]
            }
          });

          // Write headers
          let headers = [];
          if (sheetName === 'المنتجات') {
            headers = [['الاسم', 'SKU', 'الباركود', 'التصنيف', 'المخزون', 'التكلفة', 'سعر البيع بالتجزئة', 'تاريخ الصلاحية']];
          } else if (sheetName === 'العملاء') {
            headers = [['الاسم', 'الهاتف', 'العنوان', 'الفئة', 'الرصيد', 'إجمالي المشتريات']];
          } else {
            // Customer tab headers
            headers = [[
              'رقم الفاتورة',
              'التاريخ',
              'المنتجات المشتراة',
              'المجموع الفرعي',
              'الخصم %',
              'الضريبة %',
              'الإجمالي',
              'المدفوع',
              'المتبقي',
              'طريقة الدفع'
            ]];
          }

          await sheets.spreadsheets.values.update({
            spreadsheetId,
            range: `${sheetName}!A1`,
            valueInputOption: 'RAW',
            requestBody: { values: headers }
          });
        }

        if (type === 'INSERT') {
          // Append to sheet
          await sheets.spreadsheets.values.append({
            spreadsheetId,
            range: `${sheetName}!A:A`,
            valueInputOption: 'RAW',
            requestBody: { values: [rowValues] }
          });
        } else if (type === 'UPDATE') {
          // Find and update row, or append if not found
          const res = await sheets.spreadsheets.values.get({
            spreadsheetId,
            range: `${sheetName}!A:Z`
          });
          const rows = res.data.values || [];
          const headers = rows[0] || [];
          const matchIdx = headers.indexOf(matchCol);
          
          let rowIdx = -1;
          if (matchIdx !== -1) {
            rowIdx = rows.findIndex((r, idx) => idx > 0 && r[matchIdx] === String(matchVal));
          }

          if (rowIdx !== -1) {
            // Update existing row (rowIdx is 0-based, Sheets is 1-based)
            await sheets.spreadsheets.values.update({
              spreadsheetId,
              range: `${sheetName}!A${rowIdx + 1}`,
              valueInputOption: 'RAW',
              requestBody: { values: [rowValues] }
            });
          } else {
            // Append if row not found
            await sheets.spreadsheets.values.append({
              spreadsheetId,
              range: `${sheetName}!A:A`,
              valueInputOption: 'RAW',
              requestBody: { values: [rowValues] }
            });
          }
        }
      }

      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ error: 'Unknown action or missing arguments' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
