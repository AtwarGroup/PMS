-- Project-local pg_cron; in-app notifications only. No email or external transfer.
select cron.schedule('it-support-solution-reminders','0 * * * *','select private.it_support_solution_reminders();');
