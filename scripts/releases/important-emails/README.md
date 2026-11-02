# Important transactional email

Scope: current fleet approvals and advance/reimbursement payments; stopped-vehicle emergencies; recruitment request/offer reviews; critical IT incidents, technical purchase reviews and payment approvals/disbursement; fleet document expiry digests. Ordinary comments, ordinary tasks, policies and routine settlements do not use this queue. Existing task/candidate email services are unchanged.

Recipient identities and work addresses come from active profiles and the current workflow owner functions. Document recipients are the fleet owner, current driver and direct manager, subject to module access. No salary, candidate name, attachment or free-text request description is included. Links open the authenticated current record in one.atwargroup.com.

The cron worker scans every minute without a logged-in browser. A recipient receives one initial mail for the current stage, one reminder after its existing workflow deadline (at least 24h after the initial mail), and one escalation after the workflow's escalation deadline and at least 24h after the reminder. Fleet uses configured stage/escalation days, recruitment uses its working-day deadlines, IT uses the ticket SLA where available. Document phases are the configured lead threshold, 15 days and expired. Renewal/closure/owner/access changes invalidate unsent work.

Queues and invocation hashes are private, RLS enabled and inaccessible to clients. The Edge Function requires a five-minute, single-use scheduler nonce, authenticated through service-role-only RPCs. The queue uses atomic leases, frozen digest batches, provider idempotency and bounded retries. Ambiguous attempts older than 20h are quarantined for manual review. Delivery status `sent` means provider acceptance, not proof of inbox delivery.

Validation: rollback SQL tests on staging and production for auth, replay denial, disabled flag, deduplication, claims, stale leases, deactivated recipients, grouped document isolation and retry quarantine. Staging source tests cover recruitment owners, closure, critical versus ordinary IT and document 15-day/expired/renewed phases. Mocked worker tests cover provider requests, escaping, current links, retry classifications and cancellation before send. A production readiness probe and first provider acceptances were checked before reporting activation.

Operational pause (retains all records):

```sql
update private.important_email_settings set enabled=false where id;
```

Resume after review:

```sql
update private.important_email_settings set enabled=true where id;
```

Inspect without addresses or sensitive payloads:

```sql
select status,count(*),count(distinct batch_id) as messages,max(last_error)
from private.important_email_outbox group by status;
```

Staging is deployed but remains disabled. Do not enable sending to real company addresses from staging. Tests are transactional and do not call the email provider.
