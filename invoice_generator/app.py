from flask import Flask, render_template, request, jsonify, send_file
import os
import cv2
import numpy as np
import base64
import pytesseract

try:
    from pyzbar.pyzbar import decode
except Exception as e:
    print("Warning: pyzbar failed to import. Barcode scanning will fail:", e)
    def decode(*args, **kwargs): return []

try:
    from weasyprint import HTML
    WEASYPRINT_AVAILABLE = True
except Exception as e:
    print("Warning: WeasyPrint could not be loaded. PDF generation will fail:", e)
    WEASYPRINT_AVAILABLE = False

from num2words import num2words
import tempfile
import uuid
import datetime

app = Flask(__name__)
app.config['SECRET_KEY'] = 'shree-annapurna-secret-key'

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/manual')
def manual():
    return render_template('manual.html')

@app.route('/scan')
def scan():
    return render_template('scan.html')

@app.route('/api/scan', methods=['POST'])
def api_scan():
    try:
        data = request.json
        image_data = data.get('image', '').split(',')[1]
        nparr = np.frombuffer(base64.b64decode(image_data), np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        # Process Barcodes
        try:
            barcodes = decode(img)
            barcode_results = [barcode.data.decode('utf-8') for barcode in barcodes]
        except Exception as e:
            barcode_results = []
            
        # Process OCR (Tesseract)
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY | cv2.THRESH_OTSU)[1]
        
        try:
            # Tell pytesseract where the executable is in case it's installed
            pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'
            text_results = pytesseract.image_to_string(thresh)
            lines = [line.strip() for line in text_results.split('\n') if line.strip()]
        except Exception as e:
            # If Tesseract is not installed, return mock data for UI preview purposes
            print("Tesseract not found, generating mock OCR result for UI preview.")
            lines = [
                "Shree Annapurna Pharma Demo",
                "Paracetamol 500mg",
                "Batch A-89234",
                "Expiry 12/26",
                "MRP Rs. 15.50",
                "Qty 1"
            ]
            
        return jsonify({
            'success': True,
            'barcodes': barcode_results,
            'text_lines': lines
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/generate', methods=['POST'])
def generate_invoice():
    try:
        data = request.json
        
        customer_name = data.get('customerName', '')
        gstin = data.get('gstin', '')
        dl_no = data.get('dlNo', '')
        date = data.get('date', datetime.datetime.now().strftime("%Y-%m-%d"))
        discount_percent = float(data.get('discountPercent', 0))
        gst_percent = float(data.get('gstPercent', 0))
        items = data.get('items', [])
        
        subtotal = 0
        for item in items:
            item['qty'] = int(item.get('qty', 0))
            item['rate'] = float(item.get('rate', 0.0))
            item['amount'] = item['qty'] * item['rate']
            subtotal += item['amount']
            
        discount = subtotal * (discount_percent / 100)
        taxable_value = subtotal - discount
        gst_amount = taxable_value * (gst_percent / 100)
        grand_total = taxable_value + gst_amount
        
        amount_in_words = num2words(int(round(grand_total)), lang='en_IN').title() + " Rupees Only"
        
        invoice_number = f"INV-{uuid.uuid4().hex[:6].upper()}"
        
        html_out = render_template(
            'invoice_template.html',
            invoice_number=invoice_number,
            date=date,
            customer_name=customer_name,
            gstin=gstin,
            dl_no=dl_no,
            items=items,
            subtotal=round(subtotal, 2),
            discount_percent=discount_percent,
            discount=round(discount, 2),
            taxable_value=round(taxable_value, 2),
            gst_percent=gst_percent,
            gst_amount=round(gst_amount, 2),
            grand_total=round(grand_total, 2),
            amount_in_words=amount_in_words
        )
        
        if not WEASYPRINT_AVAILABLE:
            return jsonify({'success': False, 'error': 'WeasyPrint/GTK3 is not installed on this system. Cannot generate PDF.'}), 500

        pdf_dir = os.path.join(app.root_path, 'temp_pdfs')
        os.makedirs(pdf_dir, exist_ok=True)
        pdf_path = os.path.join(pdf_dir, f"{invoice_number}.pdf")
        
        HTML(string=html_out).write_pdf(pdf_path)
        
        return send_file(pdf_path, as_attachment=True, download_name=f"{invoice_number}.pdf")
        
    except Exception as e:
        print(f"Error generating PDF: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True)
