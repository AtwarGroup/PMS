import {readAllRows} from './paged-read.mjs?v=2.8.0';

// Summary/approval inputs only. Keep task bodies and legacy payloads off the home page.
export const DASHBOARD_TASK_COLUMNS = 'id,status,assignee_id,creator_id,delegated_by_id,due_date,start_date,completed_at,actual_end_date,updated_at,task_type,project_id,deleted_at,approval_commissioner_id';

// A failed source stays unavailable; it must never become a successful empty list.
export async function readDashboardData(sb, profile, allowed = () => true) {
  const read = async (makeQuery, enabled = true) => {
    if (!enabled) return {data: [], error: null};
    try { return {data: await readAllRows(makeQuery), error: null}; }
    catch (error) { return {data: null, error}; }
  };
  const [tasks, followups, people, projects, announcements] = await Promise.all([
    read(() => sb.from('tasks').select(DASHBOARD_TASK_COLUMNS).is('deleted_at', null).order('updated_at', {ascending:false}), allowed('tasks')),
    read(() => sb.from('follow_ups').select('*').eq('owner_id', profile.id), allowed('workspace')),
    read(() => {
      let query = sb.from('profiles').select('id,manager_id');
      return profile.role === 'manager' ? query.eq('manager_id', profile.id) : query.eq('active', true).eq('status', 'active');
    }, allowed('tasks') && profile.role !== 'employee'),
    read(() => sb.from('projects').select('id,manager_id,sponsor_id,deleted_at').is('deleted_at', null), allowed('tasks')),
    (async () => {
      try { return await sb.from('announcements').select('*').eq('status','PUBLISHED').lte('starts_at',new Date().toISOString()).order('importance',{ascending:false}).order('starts_at',{ascending:false}).limit(3); }
      catch (error) { return {data:null,error}; }
    })(),
  ]);
  return {tasks, followups, people, projects, announcements};
}
