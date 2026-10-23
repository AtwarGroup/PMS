// Counts describe employee records; login accounts are a separate population.
export function employeePopulation(records, accounts = []) {
  if (!Array.isArray(records)) throw new TypeError('Employee directory unavailable');
  const linked = new Set(records.map(r => r.profile_id).filter(Boolean));
  return {
    total: records.length,
    active: records.filter(r => r.login_active).length,
    waiting: records.filter(r => !r.profile_id).length,
    linked: records.filter(r => r.profile_id).length,
    otherAccounts: accounts.filter(a => !linked.has(a.id)).length,
  };
}

export async function loadHomeEmployeeCount(sb, allowed, count, scope) {
  if (!allowed) return;
  try {
    // PostgREST builders are thenables; they do not expose Promise.catch().
    const {data, error} = await sb.rpc('employee_master_list');
    if (error || !Array.isArray(data)) throw error || new Error('Directory unavailable');
    count.textContent = employeePopulation(data).total;
    scope.textContent = 'سجلات الموظفين ضمن نطاق اطلاعك';
    return true;
  } catch {
    count.textContent = '—';
    scope.textContent = 'تعذر تحميل عدد الموظفين';
    return false;
  }
}
