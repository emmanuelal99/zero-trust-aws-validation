from django.shortcuts import render, redirect, get_object_or_404
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
import json
from django.contrib import messages
from .models import Shipment, TrackingEvent, Waypoint, SupportTicket
from .serializers import ScannerPayloadSerializer
from .forms import ContactMessageForm
from .tasks import send_async_email
from django.views.decorators.csrf import csrf_exempt
from django.utils.decorators import method_decorator

# Helper to keep the view clean
def calculate_progress(events):
    if not events.exists():
        return 5
    
    latest = events.first()
    if latest.status == 'DELIVERED':
        return 100
    
    # 5% base + 25% per scan, capped at 95%
    return min(95, 5 + (events.count() * 25))

def homepage(request):
    if request.method == 'POST':
        tracking_number = request.POST.get('tracking_number', '').strip()
        if tracking_number:
            # Check if it exists here too for a faster response
            if not Shipment.objects.filter(tracking_id=tracking_number).exists():
                messages.error(request, f"Shipment {tracking_number} not found.")
                return redirect('homepage')
            return redirect('tracking_page', tracking_id=tracking_number)
    return render(request, 'shipping/index.html')



def tracking_page(request, tracking_id):
    """
    Handles the core shipment tracking logic, enabling near real-time
    visibility across the delivery lifecycle.

    Key Features:

   1. Error Handling:
   Invalid tracking IDs are redirected to the homepage,
   with a session-based alert to inform the user.

   2. IoT Integration:
   Computes a dynamic progress percentage (5%–100%)
   using historical scan data from the Virtual Warehouse Scanner [cite: 3, 6, 9].

   3. Geospatial Mapping:
   Generates a JSON payload for Leaflet.js,
   allowing dynamic route visualisation and hub marker rendering.
   """
    try:
        shipment = Shipment.objects.get(tracking_id=tracking_id)
    except Shipment.DoesNotExist:
        # This pins the error to the user's session
        messages.error(request, f"No shipment found with ID: {tracking_id}")
        return redirect('homepage')
    

    events = shipment.events.all().order_by('-timestamp')
    
    # Context Construction
    context = {
        'shipment': shipment,
        'waypoints': shipment.waypoints.all(),
        'events': events,
        'current_status': events.first() if events.exists() else None,
        'progress_percent': calculate_progress(events),
        'waypoints_json': json.dumps([
            {'name': wp.location_name, 'lat': wp.latitude, 'lng': wp.longitude, 'status': wp.status} 
            for wp in shipment.waypoints.all()
        ]),
    }
    return render(request, 'shipping/tracking.html', context)




def about_page(request):
    return render(request, 'shipping/about.html')

def service_page(request):
    return render(request, 'shipping/service.html')


def submit_support_ticket(request, tracking_id):
    if request.method == 'POST':
        # Find the specific shipment
        shipment = get_object_or_404(Shipment, tracking_id=tracking_id)
        
        # Grab the data from the HTML form
        email = request.POST.get('customer_email')
        message = request.POST.get('customer_message')
        
        # Save it to the database
        if email and message:
            SupportTicket.objects.create(
                shipment=shipment,
                customer_email=email,
                customer_message=message
            )
            messages.success(request, "Your message has been sent to our dispatch team! We will reply shortly.")
        else:
            messages.error(request, "Please provide both an email and a message.")
            
    # Redirect back to the tracking page
    return redirect('tracking_page', tracking_id=tracking_id)


# THE API FOR THE SCANNER
@method_decorator(csrf_exempt, name='dispatch') # allows scanner script to bypass CSRF for this endpoint
class ScannerUpdateAPI(APIView):
    def post(self, request):
        serializer = ScannerPayloadSerializer(data=request.data)
        
        if serializer.is_valid():
            data = serializer.validated_data
            shipment = get_object_or_404(Shipment, tracking_id=data['tracking_id'])

            # Log history event
            TrackingEvent.objects.create(
                shipment=shipment,
                location=data['location'],
                status=data['status'],
                description=data['description']
            )

            # Update route progress: Find waypoints with this name and mark Completed
            shipment.waypoints.filter(location_name=data['location']).update(status='COMPLETED')

            return Response({"success": "Tracking updated"}, status=status.HTTP_201_CREATED)
            
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
    


def contact_page(request):
    if request.method == 'POST':
        form = ContactMessageForm(request.POST)
        
        if form.is_valid():
            new_lead = form.save()
            
            # trigger celery task to send email to admin team
            send_async_email.delay(
                subject=f"New Website Lead: {new_lead.service_enquiry}",
                message=f"Name: {new_lead.first_name}\nEmail: {new_lead.email}\nMessage: {new_lead.message}",
                recipient_list=['admin@yourlogistics.com']
            )
            
            messages.success(request, "Thank you! Your message has been sent.")
            return redirect('contact_page')
        else:
            
            print("FORM ERRORS:", form.errors) 
            messages.error(request, "Submission failed. Please check the form.")
            
    return render(request, 'shipping/contact.html')