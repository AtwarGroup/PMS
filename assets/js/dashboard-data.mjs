import {readAllRows} from './paged-read.mjs?v=2.8.0';

// A failed source stays unavailable; it must never become a successful empty list.
export async function readDashboardData(sb, profile, allowed = () => true) {
  const read = async (makeQuery, enabled = true) => {
    if (!enabled) return {data: [], error: null};
    try { return {data: await readAllRows(makeQuery), error: null}; }
    catch (error) { return {data: null, error}; }
  };
  const [tasks, followups, people, projects, announcements] = await Promise.all([
    read(() => sb.from('tasks').select('*').is('deleted_at', null).order('updated_at', {ascending:false}), allowed('tasks')),
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
