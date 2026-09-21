(function(){
  const icon={success:'✓',error:'!',warning:'!',info:'i'};
  function region(){
    let node=document.querySelector('.atwar-feedback-region');
    if(!node){node=document.createElement('div');node.className='atwar-feedback-region';node.setAttribute('aria-live','polite');node.setAttribute('aria-atomic','true');document.body.append(node)}
    return node;
  }
  function toast(message,options={}){
    if(typeof options==='string')options={type:options};
    const {type='info',title='',duration=4200}=options;
    const node=document.createElement('div');node.className=`atwar-toast ${type}`;node.setAttribute('role',type==='error'?'alert':'status');
    const mark=document.createElement('span');mark.className='atwar-toast-icon';mark.textContent=icon[type]||icon.info;
    const copy=document.createElement('span'),strong=document.createElement('b'),small=document.createElement('small');strong.textContent=title||({success:'تمت العملية',error:'تعذر تنفيذ العملية',warning:'تنبيه',info:'معلومة'}[type]);small.textContent=String(message||'');copy.append(strong,small);
    const close=document.createElement('button');close.type='button';close.setAttribute('aria-label','إغلاق الرسالة');close.textContent='×';close.onclick=()=>node.remove();node.append(mark,copy,close);region().append(node);
    if(duration>0)setTimeout(()=>node.remove(),duration);return node;
  }
  function saveState(target,state='idle',message=''){
    const node=typeof target==='string'?document.querySelector(target):target;if(!node)return;
    node.classList.add('atwar-save-state');node.classList.remove('saving','saved','error');if(state!=='idle')node.classList.add(state);
    node.textContent=message||({idle:'',saving:'جارٍ الحفظ…',saved:'✓ تم الحفظ',error:'تعذر الحفظ'}[state]||'');node.setAttribute('role',state==='error'?'alert':'status');
  }
  function confirmDialog({title='تأكيد الإجراء',message='',confirmText='تأكيد',cancelText='إلغاء',danger=false}={}){
    return new Promise(resolve=>{
      const backdrop=document.createElement('div');backdrop.className='atwar-dialog-backdrop';
      const dialog=document.createElement('section');dialog.className='atwar-dialog';dialog.setAttribute('role','dialog');dialog.setAttribute('aria-modal','true');
      const head=document.createElement('header');head.className='atwar-dialog-head';const h=document.createElement('h2');h.textContent=title;head.append(h);
      const body=document.createElement('div');body.className='atwar-dialog-body';body.textContent=message;
      const actions=document.createElement('footer');actions.className='atwar-dialog-actions';const ok=document.createElement('button'),cancel=document.createElement('button');ok.type=cancel.type='button';ok.className=`atwar-btn ${danger?'danger':'primary'}`;cancel.className='atwar-btn';ok.textContent=confirmText;cancel.textContent=cancelText;actions.append(ok,cancel);dialog.append(head,body,actions);backdrop.append(dialog);document.body.append(backdrop);
      const done=value=>{backdrop.remove();resolve(value)};ok.onclick=()=>done(true);cancel.onclick=()=>done(false);backdrop.onclick=e=>{if(e.target===backdrop)done(false)};dialog.onkeydown=e=>{if(e.key==='Escape')done(false)};setTimeout(()=>ok.focus(),0);
    });
  }
  function promptDialog({title='إدخال البيانات',message='',value='',placeholder='',confirmText='حفظ',cancelText='إلغاء',multiline=true,required=false}={}){
    return new Promise(resolve=>{
      const backdrop=document.createElement('div');backdrop.className='atwar-dialog-backdrop';
      const dialog=document.createElement('section');dialog.className='atwar-dialog';dialog.setAttribute('role','dialog');dialog.setAttribute('aria-modal','true');
      const head=document.createElement('header');head.className='atwar-dialog-head';const h=document.createElement('h2');h.textContent=title;head.append(h);
      const body=document.createElement('div');body.className='atwar-dialog-body';if(message){const p=document.createElement('p');p.textContent=message;body.append(p)}
      const input=document.createElement(multiline?'textarea':'input');input.className=multiline?'atwar-textarea':'atwar-input';input.value=String(value??'');input.placeholder=placeholder;input.setAttribute('aria-label',title);body.append(input);
      const validation=document.createElement('small');validation.style.cssText='display:block;color:var(--atwar-danger-600);margin-top:6px';body.append(validation);
      const actions=document.createElement('footer');actions.className='atwar-dialog-actions';const ok=document.createElement('button'),cancel=document.createElement('button');ok.type=cancel.type='button';ok.className='atwar-btn primary';cancel.className='atwar-btn';ok.textContent=confirmText;cancel.textContent=cancelText;actions.append(ok,cancel);dialog.append(head,body,actions);backdrop.append(dialog);document.body.append(backdrop);
      const done=result=>{backdrop.remove();resolve(result)};ok.onclick=()=>{const result=input.value.trim();if(required&&!result){validation.textContent='هذا الحقل مطلوب.';input.focus();return}done(result)};cancel.onclick=()=>done(null);backdrop.onclick=e=>{if(e.target===backdrop)done(null)};input.onkeydown=e=>{if(e.key==='Escape')done(null);if(!multiline&&e.key==='Enter'){e.preventDefault();ok.click()}};setTimeout(()=>{input.focus();input.select()},0);
    });
  }
  window.AtwarUI=Object.freeze({toast,saveState,confirm:confirmDialog,prompt:promptDialog});
})();
