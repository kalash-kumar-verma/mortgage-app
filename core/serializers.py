from rest_framework import serializers
from .models import Party, Entry, JewelleryItem, BusinessSetting


class BusinessSettingSerializer(serializers.ModelSerializer):
    class Meta:
        model = BusinessSetting
        fields = '__all__'


class PartySerializer(serializers.ModelSerializer):
    class Meta:
        model = Party
        fields = '__all__'


class EntrySerializer(serializers.ModelSerializer):
    total_payable = serializers.ReadOnlyField()
    days_elapsed = serializers.ReadOnlyField()
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