from django.db import models
from django.conf import settings
from datetime import date, timedelta
import uuid

class UserProfile(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='profile')
    phone = models.CharField(max_length=15, blank=True)
    avatar_url = models.URLField(blank=True, null=True)
    business_metadata = models.JSONField(default=dict, blank=True)

    def __str__(self):
        return f"{self.user.username}'s Profile"

class BusinessSetting(models.Model):
    strict_mode = models.BooleanField(default=False)
    grace_period_days = models.IntegerField(default=5)
    five_day_logic = models.BooleanField(default=False)
    updated_at = models.DateTimeField(auto_now=True)

    def save(self, *args, **kwargs):
        self.pk = 1
        super().save(*args, **kwargs)

    @classmethod
    def load(cls):
        obj, created = cls.objects.get_or_create(pk=1)
        return obj


class Party(models.Model):
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='parties',
        null=True,  # nullable during migration; data migration sets existing records
        blank=True,
    )
    name = models.CharField(max_length=100)
    phone = models.CharField(max_length=15, blank=True)
    address = models.TextField(blank=True)
    note = models.TextField(blank=True)
    default_interest_rate = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    sync_id = models.UUIDField(default=uuid.uuid4, null=True, blank=True)
    account_number = models.CharField(max_length=20, blank=True, null=True)

    def save(self, *args, **kwargs):
        if not self.account_number:
            max_num = 0
            for p in Party.objects.exclude(account_number__isnull=True).exclude(account_number__exact=''):
                if p.account_number and p.account_number.startswith('ACC-'):
                    try:
                        num = int(''.join(filter(str.isdigit, p.account_number)))
                        if num > max_num: max_num = num
                    except ValueError:
                        pass
            self.account_number = f"ACC-{str(max_num + 1).zfill(3)}"
        super().save(*args, **kwargs)

    def __str__(self):
        return self.name


class Entry(models.Model):
    STATUS_CHOICES = [
        ('ACTIVE', 'Active'),
        ('OVERDUE', 'Overdue'),
        ('WITHDRAWN', 'Withdrawn'),
        ('CLOSED', 'Closed'),
        ('DELETED', 'Deleted'),
    ]

    sr_number = models.CharField(max_length=20, blank=True, null=True)
    party = models.ForeignKey(Party, on_delete=models.CASCADE)
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    interest = models.DecimalField(max_digits=5, decimal_places=2)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='ACTIVE')
    date = models.DateField(auto_now_add=True)
    due_date = models.DateField(null=True, blank=True)  # Explicit due date; optional
    note = models.TextField(blank=True, default='')
    closed_at = models.DateField(null=True, blank=True)
    sync_id = models.UUIDField(default=uuid.uuid4, null=True, blank=True)
    version = models.IntegerField(default=1)  # Incremented on edit — used for conflict detection

    def save(self, *args, **kwargs):
        if not self.sr_number:
            max_num = 0
            for e in Entry.objects.all():
                try:
                    num = int(''.join(filter(str.isdigit, str(e.sr_number))))
                    if num > max_num: max_num = num
                except ValueError:
                    pass
            self.sr_number = f"SR no: {max_num + 1}"
        super().save(*args, **kwargs)

    @property
    def total_payable(self):
        today = date.today()
        if self.status in ['WITHDRAWN', 'CLOSED'] and self.closed_at:
            today = self.closed_at
        elif self.due_date and self.due_date < today:
            today = self.due_date

        settings_obj = BusinessSetting.load()
        
        # Load all payments ordered by date
        payments = list(self.payments.all().order_by('date'))
        payment_dict = {}
        for p in payments:
            d = p.date.date() if hasattr(p.date, 'date') else p.date
            payment_dict[d] = payment_dict.get(d, 0.0) + float(p.amount)

        principal = float(self.amount)
        rate = float(self.interest)
        unpaid_interest = 0.0
        
        total_days = (today - self.date).days
        if total_days < 0:
            total_days = 0

        # If five-day logic applies and closed within 5 days, no interest.
        if settings_obj.five_day_logic and total_days <= 5 and not payments:
            return round(principal, 2)

        # Simulate day by day
        for day_offset in range(total_days + 1):
            current_date = self.date + timedelta(days=day_offset)
            
            # 1. Accrue Interest for the day
            if settings_obj.strict_mode:
                # Daily interest accrual
                unpaid_interest += (principal * rate) / 3000
            else:
                # Month-chunk interest accrual
                # Interest is charged upfront for the month.
                # Month 1 is charged on day 0 (unless grace period applies and we are within it, but standard is upfront).
                # Actually, current logic: if days <= grace, months=1. So 1 month is always charged if > 5 days.
                # If we exceed grace_period, we start charging.
                # Let's align with the existing math: 
                # if days <= grace: months = 1.
                # if days > grace: months = (days - grace) // 30 + 1
                # This means new months trigger when (day_offset - grace) % 30 == 0 AND day_offset >= grace.
                # Wait, at day_offset == 0, we charge 1 month upfront.
                if day_offset == 0:
                    unpaid_interest += (principal * rate) / 100
                elif day_offset > settings_obj.grace_period_days:
                    # e.g., grace=5. day 6 -> (6-5)%30 == 1. We want to charge on day 6!
                    # so if day_offset - grace_period_days == 1, charge month 2!
                    # if day_offset - grace_period_days == 31, charge month 3!
                    if (day_offset - settings_obj.grace_period_days) % 30 == 1:
                        unpaid_interest += (principal * rate) / 100

            # 2. Apply Payments for the day
            if current_date in payment_dict:
                payment_amount = payment_dict[current_date]
                # Payment first clears unpaid interest
                if payment_amount <= unpaid_interest:
                    unpaid_interest -= payment_amount
                else:
                    payment_amount -= unpaid_interest
                    unpaid_interest = 0.0
                    # Remaining reduces principal
                    principal -= payment_amount
                    if principal < 0:
                        principal = 0.0

        return round(principal + unpaid_interest, 2)


    @property
    def days_elapsed(self):
        today = date.today()
        if self.status in ['WITHDRAWN', 'CLOSED'] and self.closed_at:
            today = self.closed_at
        return (today - self.date).days

    @property
    def total_paid(self):
        return round(sum(p.amount for p in self.payments.all()), 2)

    @property
    def remaining_principal(self):
        # Calculate exactly as we do in the ledger
        payments = list(self.payments.all().order_by('date'))
        if not payments:
            return round(float(self.amount), 2)
            
        principal = float(self.amount)
        rate = float(self.interest)
        unpaid_interest = 0.0
        settings_obj = BusinessSetting.load()
        
        # We need the ledger again to find the exact remaining principal today
        payment_dict = {}
        for p in payments:
            d = p.date.date() if hasattr(p.date, 'date') else p.date
            payment_dict[d] = payment_dict.get(d, 0.0) + float(p.amount)
            
        today = date.today()
        if self.status in ['WITHDRAWN', 'CLOSED'] and self.closed_at:
            today = self.closed_at
        elif self.due_date and self.due_date < today:
            today = self.due_date
            
        total_days = max(0, (today - self.date).days)
        
        if settings_obj.five_day_logic and total_days <= 5 and not payments:
            return round(principal, 2)

        for day_offset in range(total_days + 1):
            current_date = self.date + timedelta(days=day_offset)
            if settings_obj.strict_mode:
                unpaid_interest += (principal * rate) / 3000
            else:
                if day_offset == 0:
                    unpaid_interest += (principal * rate) / 100
                elif day_offset > settings_obj.grace_period_days:
                    if (day_offset - settings_obj.grace_period_days) % 30 == 1:
                        unpaid_interest += (principal * rate) / 100

            if current_date in payment_dict:
                payment_amount = payment_dict[current_date]
                if payment_amount <= unpaid_interest:
                    unpaid_interest -= payment_amount
                else:
                    payment_amount -= unpaid_interest
                    unpaid_interest = 0.0
                    principal -= payment_amount
                    if principal < 0:
                        principal = 0.0
        return round(principal, 2)
        
    @property
    def total_accrued_interest(self):
        # Total payable = remaining principal + unpaid interest
        # Unpaid interest = total payable - remaining principal
        return round(self.total_payable - float(self.remaining_principal), 2)

    @property
    def due_date_display(self):
        """Human-readable due date string."""
        if self.due_date:
            return self.due_date.strftime('%d/%m/%Y')
        return None

    @property
    def days_remaining(self):
        """Days until due date. Negative = overdue. None if no due date."""
        if not self.due_date:
            return None
        if self.status in ['WITHDRAWN', 'CLOSED']:
            return None
        return (self.due_date - date.today()).days

    @property
    def item_release_status(self):
        items = self.jewelleryitem_set.all()
        if not items.exists():
            return 'no_items'
        statuses = set(i.release_status for i in items)
        if statuses == {'released'} or statuses == {'transferred'} or statuses <= {'released', 'transferred'}:
            return 'all_released'
        if 'held' in statuses and len(statuses) > 1:
            return 'partial'
        return 'all_held'

    def __str__(self):
        return f"{self.sr_number} - {self.party.name}"


class JewelleryItem(models.Model):
    entry = models.ForeignKey(Entry, on_delete=models.CASCADE)
    item_type = models.CharField(max_length=20)
    name = models.CharField(max_length=100)
    weight = models.FloatField(null=True, blank=True)
    note = models.TextField(blank=True, default='')
    image = models.ImageField(upload_to='items/', null=True, blank=True)
    sync_id = models.UUIDField(default=uuid.uuid4, null=True, blank=True)
    version = models.IntegerField(default=1)

    RELEASE_STATUS_CHOICES = [
        ('held', 'Held'),
        ('released', 'Released'),
        ('transferred', 'Transferred'),
    ]
    release_status = models.CharField(
        max_length=20,
        choices=RELEASE_STATUS_CHOICES,
        default='held',
    )
    release_date = models.DateField(null=True, blank=True)
    release_note = models.TextField(blank=True, default='')

    def __str__(self):
        return f"{self.name} ({self.item_type})"


# DEPRECATED: Do not use for new development. 
# Replaced by ActivityLog to ensure offline-first queue safety and prevent duplicate logs.
class AuditLog(models.Model):
    ACTION_CHOICES = [
        ('CREATE', 'Created'),
        ('EDIT', 'Edited'),
        ('DELETE', 'Deleted'),
        ('WITHDRAW', 'Withdrawn'),
        ('OVERDUE', 'Marked Overdue'),
        ('STATUS', 'Status Changed'),
        ('PAYMENT', 'Partial Payment'),
    ]
    
    entry = models.ForeignKey(Entry, on_delete=models.SET_NULL, null=True, blank=True, related_name='audit_logs')
    action = models.CharField(max_length=20, choices=ACTION_CHOICES)
    description = models.TextField()
    actor = models.CharField(max_length=100, default='Owner')
    timestamp = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-timestamp']

    def __str__(self):
        return f"[{self.action}] {self.entry} at {self.timestamp}"


class PartialPayment(models.Model):
    entry = models.ForeignKey(Entry, on_delete=models.CASCADE, related_name='payments')
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    date = models.DateTimeField(auto_now_add=True)
    note = models.TextField(blank=True, default='')
    sync_id = models.UUIDField(default=uuid.uuid4, null=True, blank=True)

    class Meta:
        ordering = ['date']

    def __str__(self):
        return f"Payment of {self.amount} for {self.entry.sr_number} on {self.date.strftime('%Y-%m-%d')}"

class ActivityLog(models.Model):
    ACTION_CHOICES = [
        ('CREATE', 'Created'),
        ('EDIT', 'Edited'),
        ('DELETE', 'Deleted'),
        ('WITHDRAW', 'Withdrawn'),
        ('PAYMENT', 'Partial Payment'),
        ('PROFILE', 'Profile Update'),
    ]
    ENTITY_CHOICES = [
        ('PARTY', 'Party'),
        ('ENTRY', 'Entry'),
        ('ITEM', 'Item'),
        ('PAYMENT', 'Payment'),
        ('PROFILE', 'Profile'),
    ]

    sync_id = models.UUIDField(default=uuid.uuid4, unique=True)
    action = models.CharField(max_length=20, choices=ACTION_CHOICES)
    entity_type = models.CharField(max_length=20, choices=ENTITY_CHOICES)
    
    # Store snapshots so log survives entity deletion
    entity_id = models.IntegerField(null=True, blank=True)
    entity_sync_id = models.CharField(max_length=50, null=True, blank=True)
    entity_name_snapshot = models.CharField(max_length=255, blank=True, default='')
    
    timestamp = models.DateTimeField()
    description = models.TextField()
    old_values = models.JSONField(null=True, blank=True)
    new_values = models.JSONField(null=True, blank=True)
    
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='activities')
    device_id = models.CharField(max_length=100, null=True, blank=True)

    class Meta:
        ordering = ['-timestamp']

    def __str__(self):
        return f"[{self.action}] {self.entity_name_snapshot} at {self.timestamp}"