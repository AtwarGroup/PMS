import {createTestDB,ids,seedAssignedVehicle} from './fleet-test-db.mjs';
import {readFile} from 'node:fs/promises';
export {ids,seedAssignedVehicle};
export async function applyFleetV2(db){for(const file of ['20261025140000_fleet_test_feedback.sql','20261025140001_fleet_receiver_handover.sql','20261025140002_fleet_handover_stage_reminders.sql','20261025140003_fleet_handover_reminder_context_fix.sql','20261025140004_fleet_cargo_part_validation.sql','20261026073000_fleet_positive_odometer.sql'])await db.exec(await readFile(new URL('../supabase/migrations/'+file,import.meta.url),'utf8'));await db.exec(await readFile(new URL('./fleet_reference_minimum_4.sql',import.meta.url),'utf8'));}
export async function currentFleetDB(){const f=await createTestDB();await applyFleetV2(f.db);return f;}
