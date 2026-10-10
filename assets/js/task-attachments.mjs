function safeExtension(name){
  const extension=String(name||'').split('.').pop().toLowerCase().replace(/[^a-z0-9]/g,'');
  return extension&&extension.length<=8?`.${extension}`:'';
}

export function createTaskAttachmentsController({
  getSupabase,
  getSelectedTask,
  getCurrentUser,
  getCurrentProfile,
  confirmAction,
  toast,
  onChanged=async()=>{}
}){
  let uploadBusy=false,cleanupPending=0,cleanupTimer=null,cleanupBusy=false;
  function scheduleCleanup(){clearTimeout(cleanupTimer);if(cleanupPending)cleanupTimer=setTimeout(()=>void retryCleanup(),60000);}
  async function retryCleanup(){
    if(cleanupBusy||!getCurrentUser()?.uid)return;cleanupBusy=true;
    try{const sb=await getSupabase();if(!sb.functions?.invoke)return;const {data,error}=await sb.functions.invoke('cleanup-task-attachments',{body:{retry:true}});if(error||data?.error){cleanupPending=Math.max(1,cleanupPending);return;}cleanupPending=data.pending||0;}
    catch{cleanupPending=Math.max(1,cleanupPending);}
    finally{cleanupBusy=false;scheduleCleanup();}
  }
  globalThis.addEventListener?.('online',()=>void retryCleanup());
  globalThis.addEventListener?.('pagehide',()=>clearTimeout(cleanupTimer));
  globalThis.addEventListener?.('pageshow',()=>void retryCleanup());
  // Persisted queue belongs to the authenticated requester, never a browser-supplied path.
  void retryCleanup();
  const deleteLocks=new Set();
  const selectedAttachment=id=>(getSelectedTask()?.attachments||[]).find(file=>String(file.id)===String(id))||null;

  async function open(id){
    const file=selectedAttachment(id);
    if(!file?.storagePath){toast('تعذر تحديد مسار المرفق.','error');return;}
    try{
      const sb=await getSupabase();
      const {data,error}=await sb.storage.from(file.storageBucket||'task-attachments').createSignedUrl(file.storagePath,120);
      if(error)throw error;
      globalThis.open(data.signedUrl,'_blank','noopener');
    }catch(error){
      console.error('Open attachment:',error);
      toast('تعذر فتح المرفق.','error');
    }
  }

  async function remove(id){
    const lockKey=String(id||'');
    if(!lockKey||deleteLocks.has(lockKey))return;
    const task=getSelectedTask();
    const file=selectedAttachment(id);
    if(!task||!file||file.sharedBatch)return;
    const confirmed=await confirmAction(`هل تريد حذف المرفق «${file.fileName||'المرفق'}» نهائيًا؟`,'حذف المرفق');
    if(!confirmed)return;
    deleteLocks.add(lockKey);
    try{
      const sb=await getSupabase();
      const result=await sb.functions.invoke('cleanup-task-attachments',{body:{id}});
      if(result.error||result.data?.error)throw new Error(result.data?.error||'تعذر إتمام طلب الحذف. أعد المحاولة.');
      await onChanged();
      cleanupPending=result.data?.pending||0;
      toast(cleanupPending?'تم حذف المرفق من المهمة؛ تنظيف الملف بانتظار إعادة المحاولة.':'تم حذف المرفق.','success');
      scheduleCleanup();
    }catch(error){
      console.error('Delete attachment:',error);
      toast(error?.message||'تعذر حذف المرفق. لا تملك الصلاحية أو أن المهمة مقفلة.','error',6000);
    }finally{
      deleteLocks.delete(lockKey);
    }
  }

  async function upload(event){
    const input=event?.target;
    const file=input?.files?.[0];
    const task=getSelectedTask();
    if(!file||!task)return;
    if(uploadBusy){input.value='';return;}
    if(file.size>10*1024*1024){toast('الحد الأعلى لحجم المرفق 10 ميجابايت.','warning');input.value='';return;}

    const taskId=String(task._relationalId||task.id||'');
    const user=getCurrentUser();
    const profile=getCurrentProfile();
    const label=document.getElementById('attachmentUploadLabel');
    const originalText=label?.textContent||'+ إضافة مرفق';
    const storagePath=`${taskId}/${crypto.randomUUID()}${safeExtension(file.name)}`;
    uploadBusy=true;
    try{
      if(label){label.textContent='جاري الرفع...';label.setAttribute('aria-disabled','true');label.classList.add('opacity-60','pointer-events-none')}
      const sb=await getSupabase();
      const uploaded=await sb.storage.from('task-attachments').upload(storagePath,file,{contentType:file.type||'application/octet-stream',upsert:false});
      if(uploaded.error)throw uploaded.error;
      const row={task_id:taskId,uploader_id:user.uid,uploader_name_snapshot:profile?.name||user.email||'',file_name:file.name,storage_path:storagePath,content_type:file.type||null,size_bytes:file.size};
      const saved=await sb.from('task_attachments').insert(row).select('id,task_id,file_name,storage_path,size_bytes,created_at').single();
      if(saved.error){await sb.storage.from('task-attachments').remove([storagePath]).catch(()=>{});throw saved.error;}
      await onChanged();
      toast('تم رفع المرفق بنجاح.','success');
    }catch(error){
      console.error('Upload attachment:',error);
      toast(error?.message||'تعذر رفع المرفق. تحقق من الصلاحية ونوع الملف.','error',6000);
    }finally{
      uploadBusy=false;
      input.value='';
      if(label){label.textContent=originalText;label.removeAttribute('aria-disabled');label.classList.remove('opacity-60','pointer-events-none')}
    }
  }

  return {open,remove,upload,retryCleanup};
}
