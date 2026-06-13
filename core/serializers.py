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
    item_release_status = serializers.ReadOnlyField()

    def get_party_name(self, obj):
        return obj.party.name

    class Meta:
        model = Entry
        fields = '__all__'

    def update(self, instance, validated_data):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            role = getattr(request.user.profile, 'role', 'owner') if hasattr(request.user, 'profile') else 'owner'
            if role != 'owner':
                protected_fields = ['amount', 'interest', 'entry_date', 'status', 'party']
                for field in protected_fields:
                    if field in validated_data and validated_data[field] != getattr(instance, field):
                        raise serializers.ValidationError(
                            {field: f"Only owners can modify the '{field}' field after creation."}
                        )
        return super().update(instance, validated_data)

    def validate_party(self, value):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            # Phase 2.5: Enforce ownership on creation
            if value.owner != request.user:
                raise serializers.ValidationError("You do not have permission to create an entry for this party.")
        return value


class JewelleryItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = JewelleryItem
        fields = '__all__'

    def validate_entry(self, value):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            if value.party.owner != request.user:
                raise serializers.ValidationError("You do not have permission to create an item for this entry.")
        return value


class UserProfileSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source='user.username', read_only=True)
    email = serializers.EmailField(source='user.email', read_only=True)
    role = serializers.CharField(read_only=True)
    
    class Meta:
        model = UserProfile
        fields = ['phone', 'avatar_url', 'business_metadata', 'username', 'email', 'role']


class PartialPaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = PartialPayment
        fields = '__all__'

    def validate_entry(self, value):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            if value.party.owner != request.user:
                raise serializers.ValidationError("You do not have permission to create a payment for this entry.")
        return value

class ActivityLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = ActivityLog
        # Prevent user client from modifying user field directly
        read_only_fields = ('user',)
        fields = '__all__'