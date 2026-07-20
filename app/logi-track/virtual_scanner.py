import requests
import json

# The URL of the API endpoint built in Django
API_URL = 'http://127.0.0.1:8000/api/scanner/', 'http://18.133.236.37/api/scanner/'

def scan_package():
    print("📦 --- VIRTUAL WAREHOUSE SCANNER --- 📦")
    tracking_id = input("Scan Barcode (Paste Tracking ID): ")
    location = input("Scanner Location (e.g., London Hub - Dock 4): ")
    status = input("Status (e.g., IN_TRANSIT, DELIVERED): ")
    description = input("Event Description: ")

    # Create the payload to send to the API
    payload = {
        'tracking_id': tracking_id,
        'location': location,
        'status': status,
        'description': description
    }

    print("\n📡 Transmitting to Logistics Mainframe...")
    
    # Send the POST request to Django API
    response = requests.post(API_URL, json=payload)

    # Check if the server accepted the scan
    if response.status_code == 201:
        print("SUCCESS: Package updated in database!")
    else:
        print("ERROR: Scan rejected.")
        print(response.text)

if __name__ == "__main__":
    scan_package()