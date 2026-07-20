from rest_framework import serializers


class ScannerPayloadSerializer(serializers.Serializer):
    tracking_id = serializers.CharField(max_length=50)
    location = serializers.CharField(max_length=255)
    status = serializers.CharField(max_length=50)
    description = serializers.CharField(max_length=255)
