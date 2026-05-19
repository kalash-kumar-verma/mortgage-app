from rest_framework import serializers
from .models import Party, Entry, JewelleryItem, BusinessSetting, UserProfile, PartialPayment, ActivityLog


class BusinessSettingSerializer(serializers.ModelSerializer):
    class Meta:
        model = BusinessSetting
        fields = '__all__'


class PartySerializer(serializers.ModelSerializer):
    class Meta:
        model = Party
        # Exclude owner from the serialized output (it's an internal FK)
        exclude = ['owner']


class EntrySerializer(serializers.ModelSerializer):
    total_payable = serializers.ReadOnlyField()
    days_elapsed = serializers.ReadOnlyField()
    due_date_display = serializers.ReadOnlyField()
    days_remaining = serializers.ReadOnlyField()
    total_paid = serializers.ReadOnlyField()
    remaining_principal = serializers.ReadOnlyField()
    total_accrued_interest = serializers.ReadOnlyField()
    party_name = serializers.SerializerMethodField()

    def get_party_name(self, obj):
        return obj.party.name

    class Meta:
        model = Entry
        fields = '__all__'


class JewelleryItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = JewelleryItem
        fields = '__all__'


class UserProfileSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source='user.username', read_only=True)
    email = serializers.EmailField(source='user.email', read_only=True)
    
    class Meta:
        model = UserProfile
        fields = ['phone', 'avatar_url', 'business_metadata', 'username', 'email']


class PartialPaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = PartialPayment
        fields = '__all__'

class ActivityLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = ActivityLog
        # Prevent user client from modifying user field directly
        read_only_fields = ('user',)
        fields = '__all__'