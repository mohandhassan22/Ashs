# -*- coding: utf-8 -*-
"""
Ash Pure ERP - Excel to Supabase SQL Converter
This script reads the ASH.xlsx file, automatically detects sheets and column names,
and generates a ready-to-execute SQL script to insert the data into your Supabase database.
"""

import os
import sys

# Ensure pandas and openpyxl are installed
try:
    import pandas as pd
except ImportError:
    print("Pandas library is missing. Installing it now...")
    os.system('pip install pandas openpyxl')
    import pandas as pd

# Path to the Excel file
excel_file = "ASH.xlsx"

if not os.path.exists(excel_file):
    # Try finding it in parent or current directory
    if os.path.exists("../ASH.xlsx"):
        excel_file = "../ASH.xlsx"
    else:
        print(f"Error: {excel_file} not found in the workspace directory.")
        sys.exit(1)

print(f"Loading Excel file: {excel_file}...")
xl = pd.ExcelFile(excel_file)
sheet_names = xl.sheet_names
print(f"Detected sheets: {sheet_names}")

# Mappings for Products (Arabic & English columns to Supabase schema)
product_mappings = {
    'name': ['name', 'الاسم', 'اسم المنتج', 'المنتج', 'اسم_المنتج'],
    'sku': ['sku', 'كود', 'الرمز', 'الكود', 'كود المنتج'],
    'barcode': ['barcode', 'الباركود', 'باركود', 'رقم الباركود'],
    'category': ['category', 'الفئة', 'القسم', 'التصنيف', 'نوع المنتج'],
    'stock': ['stock', 'الكمية', 'الرصيد', 'qty', 'المخزون', 'الكمية الحالية', 'الكمية المكتوبة'],
    'cost': ['cost', 'التكلفة', 'سعر الشراء', 'سعر_الشراء', 'سعر التكلفة', 'سعر تكلفة'],
    'price_retail': ['price_retail', 'clientPrice', 'سعر البيع', 'سعر التجزئة', 'سعر_البيع', 'البيع', 'سعر العميل العادي', 'العميل العادي', 'العميل', 'سعر العميل'],
    'price_specialist': ['price_specialist', 'specialistPrice', 'سعر المتخصصة', 'متخصصة', 'سعر_المتخصصة', 'المتخصصة', 'سعر متخصصة'],
    'price_dealer': ['price_dealer', 'traderPrice', 'سعر التاجر', 'تاجر', 'سعر_التاجر', 'جملة', 'سعر الجملة', 'التاجر', 'سعر تاجر'],
    'supplier': ['supplier', 'المورد', 'اسم المورد', 'اسم_المورد'],
    'expiry': ['expiry', 'تاريخ الصلاحية', 'الانتهاء', 'تاريخ الانتهاء', 'تاريخ_الصلاحية'],
    'min_qty': ['min_qty', 'minQty', 'الحد الأدنى', 'حد الطلب', 'اقل كمية'],
    'notes': ['notes', 'ملاحظات', 'الملاحظات', 'الوصف']
}

# Mappings for Customers
customer_mappings = {
    'name': ['name', 'الاسم', 'اسم العميل', 'العميل', 'اسم_العميل'],
    'phone': ['phone', 'الهاتف', 'الموبايل', 'التليفون', 'رقم الهاتف', 'رقم الموبايل'],
    'address': ['address', 'العنوان', 'محل الاقامة'],
    'type': ['type', 'النوع', 'الفئة', 'نوع العميل', 'التصنيف'],
    'balance': ['balance', 'الرصيد', 'المديونية', 'رصيد العميل', 'المتبقي'],
    'notes': ['notes', 'ملاحظات', 'الملاحظات']
}

sql_statements = []
sql_statements.append("-- ==========================================================")
sql_statements.append("-- ASH PURE ERP - EXCEL DATA IMPORT")
sql_statements.append(f"-- Generated automatically from {excel_file}")
sql_statements.append("-- ==========================================================\n")

# Disable triggers temporarily to prevent stock/waste calculations during import if desired
sql_statements.append("ALTER TABLE public.products DISABLE TRIGGER ALL;")
sql_statements.append("ALTER TABLE public.customers DISABLE TRIGGER ALL;\n")

def map_dataframe(df, mappings):
    mapped_data = []
    for idx, row in df.iterrows():
        mapped_row = {}
        for db_col, possible_names in mappings.items():
            val = None
            for name in possible_names:
                # Direct match
                if name in df.columns:
                    val = row[name]
                    break
                # Case-insensitive match
                matching_cols = [c for c in df.columns if str(c).strip().lower() == str(name).strip().lower()]
                if matching_cols:
                    val = row[matching_cols[0]]
                    break
            
            # Format value
            if pd.isna(val) or val is None:
                mapped_row[db_col] = "NULL"
            elif db_col in ['stock', 'cost', 'price_retail', 'price_specialist', 'price_dealer', 'min_qty', 'balance']:
                try:
                    # Clean currency signs or spaces
                    cleaned = str(val).replace('ج.م', '').replace('$', '').replace(',', '').strip()
                    mapped_row[db_col] = float(cleaned)
                except ValueError:
                    mapped_row[db_col] = 0
            elif db_col == 'expiry':
                try:
                    mapped_row[db_col] = f"'{pd.to_datetime(val).strftime('%Y-%m-%d')}'"
                except:
                    mapped_row[db_col] = "NULL"
            else:
                # Text fields
                escaped = str(val).replace("'", "''").strip()
                mapped_row[db_col] = f"'{escaped}'"
        mapped_data.append(mapped_row)
    return mapped_data

# Process Sheets
products_inserted = 0
customers_inserted = 0

for sheet in sheet_names:
    df = pd.read_excel(excel_file, sheet_name=sheet)
    # Check if this sheet is for Products or Customers
    is_products = any(col in [name for names in product_mappings.values() for name in names] for col in df.columns)
    is_customers = any(col in [name for names in customer_mappings.values() for name in names] for col in df.columns) and not is_products
    
    # Force check by sheet name
    sheet_lower = sheet.lower()
    if 'product' in sheet_lower or 'منتج' in sheet_lower or 'مخزن' in sheet_lower or 'اصناف' in sheet_lower:
        is_products = True
        is_customers = False
    elif 'customer' in sheet_lower or 'عميل' in sheet_lower or 'عملاء' in sheet_lower:
        is_customers = True
        is_products = False
        
    if is_products:
        print(f"Processing sheet '{sheet}' as Products...")
        mapped = map_dataframe(df, product_mappings)
        sql_statements.append(f"-- --- PRODUCTS FROM SHEET: {sheet} ---")
        for p in mapped:
            # Also fill frontend compatibility duplicate columns (traderPrice, specialistPrice, clientPrice)
            trader_price = p['price_dealer'] if p['price_dealer'] != 'NULL' else (p['price_retail'] if p['price_retail'] != 'NULL' else 0)
            specialist_price = p['price_specialist'] if p['price_specialist'] != 'NULL' else (p['price_retail'] if p['price_retail'] != 'NULL' else 0)
            client_price = p['price_retail'] if p['price_retail'] != 'NULL' else 0
            
            cols = ['name', 'sku', 'barcode', 'category', 'stock', 'cost', 'price_retail', 'price_specialist', 'price_dealer', 'traderPrice', 'specialistPrice', 'clientPrice', 'supplier', 'expiry', 'min_qty', 'notes']
            vals = [
                p['name'], p['sku'], p['barcode'], p['category'], p['stock'], p['cost'], 
                p['price_retail'], p['price_specialist'], p['price_dealer'],
                str(trader_price), str(specialist_price), str(client_price),
                p['supplier'], p['expiry'], p['min_qty'], p['notes']
            ]
            
            sql_statements.append(
                f"INSERT INTO public.products ({', '.join(cols)}) "
                f"VALUES ({', '.join(vals)}) ON CONFLICT (sku) DO NOTHING;"
            )
            products_inserted += 1
        sql_statements.append("")
        
    elif is_customers:
        print(f"Processing sheet '{sheet}' as Customers...")
        mapped = map_dataframe(df, customer_mappings)
        sql_statements.append(f"-- --- CUSTOMERS FROM SHEET: {sheet} ---")
        for c in mapped:
            # Ensure type is valid or default
            ctype = c['type']
            if ctype != 'NULL':
                ctype_val = ctype.strip("'").lower()
                if 'تاجر' in ctype_val or 'trader' in ctype_val:
                    ctype = "'trader'"
                elif 'متخصصة' in ctype_val or 'specialist' in ctype_val:
                    ctype = "'specialist'"
                else:
                    ctype = "'client'"
            else:
                ctype = "'client'"
                
            cols = ['name', 'phone', 'address', 'type', 'balance', 'notes']
            vals = [c['name'], c['phone'], c['address'], ctype, c['balance'], c['notes']]
            
            sql_statements.append(
                f"INSERT INTO public.customers ({', '.join(cols)}) "
                f"VALUES ({', '.join(vals)});"
            )
            customers_inserted += 1
        sql_statements.append("")

# Enable triggers back
sql_statements.append("ALTER TABLE public.products ENABLE TRIGGER ALL;")
sql_statements.append("ALTER TABLE public.customers ENABLE TRIGGER ALL;\n")

# Write output file
output_file = "insert_excel_data.sql"
with open(output_file, "w", encoding="utf-8") as f:
    f.write("\n".join(sql_statements))

print("\nSuccess!")
print(f"-> Generated SQL file: {output_file}")
print(f"-> Found and prepared {products_inserted} products insert queries.")
print(f"-> Found and prepared {customers_inserted} customers insert queries.")
print("\nTo load this data into Supabase:")
print("1. Run this python script in your terminal: python convert_excel_to_sql.py")
print("2. Open the newly created file 'insert_excel_data.sql' in your editor.")
print("3. Copy the entire content and paste it into the Supabase SQL Editor, then click 'Run'.")
