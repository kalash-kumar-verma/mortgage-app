from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.models import User
from .models import Party, Entry, JewelleryItem, BusinessSetting, UserProfile

class UserProfileInline(admin.StackedInline):
    model = UserProfile
    can_delete = False
    verbose_name_plural = 'profile'

class UserAdmin(BaseUserAdmin):
    inlines = (UserProfileInline,)

admin.site.unregister(User)
admin.site.register(User, UserAdmin)


@admin.register(Party)
class PartyAdmin(admin.ModelAdmin):
    list_display = ['id', 'name', 'phone', 'default_interest_rate', 'created_at']
    search_fields = ['name', 'phone']
    list_filter = ['created_at']


@admin.register(Entry)
class EntryAdmin(admin.ModelAdmin):
    list_display = ['sr_number', 'party', 'amount', 'interest', 'status', 'date', 'closed_at']
    search_fields = ['sr_number', 'party__name']
    list_filter = ['status', 'date']
    readonly_fields = ['sr_number', 'date', 'sync_id']


@admin.register(JewelleryItem)
class JewelleryItemAdmin(admin.ModelAdmin):
    list_display = ['id', 'entry', 'item_type', 'name', 'weight']
    search_fields = ['name', 'entry__sr_number']
    list_filter = ['item_type']


@admin.register(BusinessSetting)
class BusinessSettingAdmin(admin.ModelAdmin):
    list_display = ['id', 'strict_mode', 'five_day_logic', 'grace_period_days']

    def has_add_permission(self, request):
        # Only one instance allowed
        return not BusinessSetting.objects.exists()

    def has_delete_permission(self, request, obj=None):
        return False