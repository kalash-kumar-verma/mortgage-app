from django.db import models
from django.conf import settings
from datetime import date, timedelta
import uuid

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
        # For closed/withdrawn entries, use the closure date
        if self.status in ['WITHDRAWN', 'CLOSED'] and self.closed_at:
            today = self.closed_at
        # For active entries, use due_date as the interest endpoint if it is past
        elif self.due_date and self.due_date < today:
            today = self.due_date

        days = (today - self.date).days

        settings_obj = BusinessSetting.load()

        if settings_obj.five_day_logic and days <= 5:
            interest_amount = 0
        elif settings_obj.strict_mode:
            interest_amount = (float(self.amount) * float(self.interest) * days) / 3000
        else:
            if days <= settings_obj.grace_period_days:
                months = 1
            else:
                months = max(1, (days - settings_obj.grace_period_days) // 30 + 1)
            interest_amount = (float(self.amount) * float(self.interest) * months) / 100

        return round(float(self.amount) + interest_amount, 2)

    @property
    def days_elapsed(self):
        today = date.today()
        if self.status in ['WITHDRAWN', 'CLOSED'] and self.closed_at:
            today = self.closed_at
        return (today - self.date).days

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

    def __str__(self):
        return f"{self.name} ({self.item_type})"


class AuditLog(models.Model):
    ACTION_CHOICES = [
        ('CREATE', 'Created'),
        ('EDIT', 'Edited'),
        ('DELETE', 'Deleted'),
        ('WITHDRAW', 'Withdrawn'),
        ('OVERDUE', 'Marked Overdue'),
        ('STATUS', 'Status Changed'),
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