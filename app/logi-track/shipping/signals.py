from django.db.models.signals import post_save
from django.dispatch import receiver
from geopy.geocoders import Nominatim
from geopy.distance import geodesic
from django.core.mail import send_mail
from .models import Shipment, Waypoint, Facility
from .tasks import send_async_email


def get_closest_facility(target_lat, target_lon):
    """Finds the nearest facility in the database to a given GPS coordinate."""
    facilities = Facility.objects.all()
    if not facilities:
        return None

    closest_hub = None
    shortest_distance = float('inf')
    target_coords = (target_lat, target_lon)

    for facility in facilities:
        hub_coords = (facility.latitude, facility.longitude)
        distance = geodesic(target_coords, hub_coords).miles
        
        if distance < shortest_distance:
            shortest_distance = distance
            closest_hub = facility

    return closest_hub

@receiver(post_save, sender=Shipment)
def generate_dynamic_route_and_distance(sender, instance, created, **kwargs):
    if created:
        geolocator = Nominatim(user_agent="devops_logistics_project")
        raw_route_data = []
        total_mileage = 0.0
        
        try:
            # 1. Geocode Origin and Destination
            origin_geo = geolocator.geocode(instance.origin)
            dest_geo = geolocator.geocode(instance.destination)
            
            if origin_geo and dest_geo:
                origin_coords = (origin_geo.latitude, origin_geo.longitude)
                dest_coords = (dest_geo.latitude, dest_geo.longitude)
                
                # 2. Calculate the direct distance first to act as the gatekeeper
                direct_distance = geodesic(origin_coords, dest_coords).miles
                
                # Always start the route with the Origin
                raw_route_data.append({'name': instance.origin, 'lat': origin_geo.latitude, 'lon': origin_geo.longitude})
                
                # --- THE HYBRID DISTANCE ENGINE ---
                # Set  threshold (e.g., 50 miles)
                if direct_distance >= 50: 
                    # It's a long distance! Look for hubs.
                    origin_hub = get_closest_facility(origin_geo.latitude, origin_geo.longitude)
                    dest_hub = get_closest_facility(dest_geo.latitude, dest_geo.longitude)
                    
                    if origin_hub and dest_hub:
                        if origin_hub == dest_hub:
                            # They share the same regional hub (3 stops)
                            raw_route_data.append({'name': origin_hub.name, 'lat': origin_hub.latitude, 'lon': origin_hub.longitude})
                        else:
                            # It's a national route across two hubs (4 stops)
                            raw_route_data.append({'name': origin_hub.name, 'lat': origin_hub.latitude, 'lon': origin_hub.longitude})
                            raw_route_data.append({'name': dest_hub.name, 'lat': dest_hub.latitude, 'lon': dest_hub.longitude})
                
                # Always end the route with the Destination
                raw_route_data.append({'name': instance.destination, 'lat': dest_geo.latitude, 'lon': dest_geo.longitude})
                
            else:
                # Fallback if map lookup fails
                raw_route_data = [{'name': instance.origin, 'lat': 0.0, 'lon': 0.0}, {'name': instance.destination, 'lat': 0.0, 'lon': 0.0}]
                
        except Exception as e:
            print(f"Routing Error: {e}")
            raw_route_data = [{'name': instance.origin, 'lat': 0.0, 'lon': 0.0}, {'name': instance.destination, 'lat': 0.0, 'lon': 0.0}]

        # 3. Clean duplicates (prevents errors if the user's address IS the hub)
        final_route = []
        for stop in raw_route_data:
            if not final_route or final_route[-1]['name'] != stop['name']:
                final_route.append(stop)

        # 4. Calculate actual driving mileage and save waypoints
        previous_coords = None
        for index, stop_info in enumerate(final_route, start=1):
            current_coords = (stop_info['lat'], stop_info['lon'])
            
            if previous_coords and current_coords != (0.0, 0.0) and previous_coords != (0.0, 0.0):
                total_mileage += geodesic(previous_coords, current_coords).miles
                
            previous_coords = current_coords

            Waypoint.objects.create(
                shipment=instance,
                location_name=stop_info['name'],
                latitude=stop_info['lat'],
                longitude=stop_info['lon'],
                stop_number=index,
                status='COMPLETED' if index == 1 else 'PENDING'
            )

        # 5. Save final mileage
        instance.total_distance = round(total_mileage, 1)
        instance.save(update_fields=['total_distance'])



@receiver(post_save, sender=Shipment)
def send_shipment_creation_email(sender, instance, created, **kwargs):
    """Listens for new shipments and sends a background welcome email."""
    if created and instance.customer_email:
        
        subject = f"LogiTrack: Your Shipment #{instance.tracking_id} has been created"
        
        message = f"""
        Hello,
        
        Your new shipment has been officially registered in our logistics network.
        
        Tracking ID: {instance.tracking_id}
        Origin: {instance.origin}
        Destination: {instance.destination}
        
        You will receive updates as it begins transit. Thank you for choosing LogiTrack!
        """
        
        send_async_email.delay(
            subject=subject,
            message=message,
            recipient_list=[instance.customer_email]
        )