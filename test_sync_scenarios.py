import os
import django
import json

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'mortgage_api.settings')
django.setup()

from django.test import TestCase
from django.test import Client
from core.models import Party, Entry, JewelleryItem, BusinessSetting
from django.contrib.auth.models import User

class SyncScenariosTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username='testuser', password='password123')
        self.client_a = Client()
        self.client_b = Client()
        
        # Login A
        response = self.client_a.post('/api/login/', {'username': 'testuser', 'password': 'password123'}, content_type='application/json')
        self.token_a = response.json()['token']
        self.client_a.defaults['HTTP_AUTHORIZATION'] = f'Token {self.token_a}'

        # Login B
        response = self.client_b.post('/api/login/', {'username': 'testuser', 'password': 'password123'}, content_type='application/json')
        self.token_b = response.json()['token']
        self.client_b.defaults['HTTP_AUTHORIZATION'] = f'Token {self.token_b}'

    def test_scenario_1_offline_creation_and_withdraw(self):
        print("\n--- Running Scenario 1 ---")
        # Simulating Device A queue processing (FIFO)
        
        # 1. Create Party
        party_resp = self.client_a.post('/api/parties/', {'name': 'John Doe', 'phone': '1234567890', 'address': '123 Street'}, content_type='application/json')
        self.assertEqual(party_resp.status_code, 201)
        party_id = party_resp.json()['id']
        
        # 2. Create Entry
        entry_resp = self.client_a.post('/api/entries/', {'party': party_id, 'amount': '5000', 'interest': '2.0'}, content_type='application/json')
        self.assertEqual(entry_resp.status_code, 201)
        entry_id = entry_resp.json()['id']
        
        # 3. Add Item
        item_resp = self.client_a.post('/api/items/', {'entry': entry_id, 'item_type': 'Gold', 'name': 'Ring', 'weight': '10.0'})
        self.assertEqual(item_resp.status_code, 201, item_resp.content)
        
        # 4. Withdraw
        withdraw_resp = self.client_a.post(f'/api/entries/{entry_id}/withdraw/')
        self.assertEqual(withdraw_resp.status_code, 200)

        # Verification
        self.assertEqual(Party.objects.count(), 1)
        self.assertEqual(Entry.objects.count(), 1)
        self.assertEqual(JewelleryItem.objects.count(), 1)
        
        entry = Entry.objects.first()
        self.assertEqual(entry.status, 'WITHDRAWN')
        print("Scenario 1 verified successfully.")

    def test_scenario_2_parent_deletion_conflict(self):
        print("\n--- Running Scenario 2 ---")
        # Setup: Create Party and Entry
        party_resp = self.client_a.post('/api/parties/', {'name': 'Jane Doe', 'phone': '0987654321', 'address': '456 Ave'}, content_type='application/json')
        party_id = party_resp.json()['id']
        
        entry_resp = self.client_a.post('/api/entries/', {'party': party_id, 'amount': '1000', 'interest': '1.5'}, content_type='application/json')
        entry_id = entry_resp.json()['id']

        item_resp = self.client_a.post('/api/items/', {'entry': entry_id, 'item_type': 'Silver', 'name': 'Chain', 'weight': '20.0'})
        self.assertEqual(item_resp.status_code, 201, item_resp.content)
        item_id = item_resp.json()['id']
        item_version = item_resp.json()['version']

        # Device A deletes the party (which cascades and deletes the entry and item)
        del_resp = self.client_a.delete(f'/api/parties/{party_id}/')
        self.assertEqual(del_resp.status_code, 204)
        self.assertEqual(Party.objects.count(), 0)

        # Device B attempts to modify the JewelleryItem
        edit_resp = self.client_b.patch(f'/api/items/{item_id}/', {'name': 'Thick Chain', 'version': item_version}, content_type='application/json')
        # Expect 404 because the parent/item is deleted
        self.assertEqual(edit_resp.status_code, 404)
        print("Scenario 2 verified successfully: parent deletion rule enforced (404 caught).")

    def test_scenario_3_withdraw_vs_edit(self):
        print("\n--- Running Scenario 3 ---")
        # Setup
        party_resp = self.client_a.post('/api/parties/', {'name': 'Bob', 'phone': '111', 'address': 'xyz'}, content_type='application/json')
        party_id = party_resp.json()['id']
        
        entry_resp = self.client_a.post('/api/entries/', {'party': party_id, 'amount': '2000', 'interest': '1.0'}, content_type='application/json')
        entry_id = entry_resp.json()['id']
        entry_version = entry_resp.json()['version']

        # Device A withdraws
        withdraw_resp = self.client_a.post(f'/api/entries/{entry_id}/withdraw/')
        self.assertEqual(withdraw_resp.status_code, 200)

        # Device B attempts to edit
        edit_resp = self.client_b.patch(f'/api/entries/{entry_id}/', {'amount': '3000', 'version': entry_version}, content_type='application/json')
        
        # Expect 409 Conflict due to WITHDRAWN status
        self.assertEqual(edit_resp.status_code, 409)
        self.assertIn('withdrawn', edit_resp.json()['message'].lower())
        print("Scenario 3 verified successfully: WITHDRAWN lock works.")

    def test_scenario_4_concurrent_edit_conflict(self):
        print("\n--- Running Scenario 4 ---")
        party_resp = self.client_a.post('/api/parties/', {'name': 'Alice', 'phone': '222', 'address': 'abc'}, content_type='application/json')
        party_id = party_resp.json()['id']
        
        entry_resp = self.client_a.post('/api/entries/', {'party': party_id, 'amount': '500', 'interest': '2.0'}, content_type='application/json')
        entry_id = entry_resp.json()['id']
        initial_version = entry_resp.json()['version']

        # Device A edits successfully (version moves to 2)
        edit_a_resp = self.client_a.patch(f'/api/entries/{entry_id}/', {'amount': '600', 'version': initial_version}, content_type='application/json')
        self.assertEqual(edit_a_resp.status_code, 200)

        # Device B edits with initial_version (stale)
        edit_b_resp = self.client_b.patch(f'/api/entries/{entry_id}/', {'amount': '700', 'version': initial_version}, content_type='application/json')
        
        # Expect 409 Version Conflict
        self.assertEqual(edit_b_resp.status_code, 409)
        self.assertTrue(edit_b_resp.json()['conflict'])
        print("Scenario 4 verified successfully: Optimistic version conflict caught.")

    def test_scenario_6_offline_delete_vs_server_update(self):
        print("\n--- Running Scenario 6 (Offline delete vs server update) ---")
        party_resp = self.client_a.post('/api/parties/', {'name': 'Charlie', 'phone': '333', 'address': 'def'}, content_type='application/json')
        party_id = party_resp.json()['id']
        
        entry_resp = self.client_a.post('/api/entries/', {'party': party_id, 'amount': '1500', 'interest': '2.0'}, content_type='application/json')
        entry_id = entry_resp.json()['id']
        initial_version = entry_resp.json()['version']

        # Device B updates the entry
        edit_b_resp = self.client_b.patch(f'/api/entries/{entry_id}/', {'amount': '1600', 'version': initial_version}, content_type='application/json')
        self.assertEqual(edit_b_resp.status_code, 200)

        # Device A deletes the entry using the old version
        del_a_resp = self.client_a.delete(f'/api/entries/{entry_id}/?version={initial_version}')
        
        # Expect 409 Version Conflict
        self.assertEqual(del_a_resp.status_code, 409)
        self.assertTrue(del_a_resp.json()['conflict'])
        print("Scenario 6 verified successfully: Offline delete vs server update conflict caught.")

    def test_scenario_7_queue_ordering(self):
        print("\n--- Running Scenario 7 (Queue Ordering verification) ---")
        # In a real app, the queue handles this, but we verify the API allows a sequence of actions smoothly.
        # Create -> Edit -> Delete -> Restore (by creating again)
        
        # 1. Create
        party_resp = self.client_a.post('/api/parties/', {'name': 'David', 'phone': '444', 'address': 'ghi'}, content_type='application/json')
        self.assertEqual(party_resp.status_code, 201)
        party_id = party_resp.json()['id']
        
        # 2. Edit
        edit_resp = self.client_a.patch(f'/api/parties/{party_id}/', {'phone': '555'}, content_type='application/json')
        self.assertEqual(edit_resp.status_code, 200)

        # 3. Delete
        del_resp = self.client_a.delete(f'/api/parties/{party_id}/')
        self.assertEqual(del_resp.status_code, 204)

        # 4. Restore (Create again)
        party_resp2 = self.client_a.post('/api/parties/', {'name': 'David', 'phone': '555', 'address': 'ghi'}, content_type='application/json')
        self.assertEqual(party_resp2.status_code, 201)
        
        self.assertEqual(Party.objects.filter(name='David').count(), 1)
        print("Scenario 7 (API sequential logic) verified successfully.")

