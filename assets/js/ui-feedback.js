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
  let dialogSequence=0,openDialogs=0,savedBodyOverflow='';
  function prepareDialog(dialog,head,body,cancel,initialFocus){
    const previous=document.activeElement;
    if(openDialogs++===0){savedBodyOverflow=document.body.style.overflow;document.body.style.overflow='hidden';}
    const titleId=`atwar-dialog-title-${++dialogSequence}`,bodyId=`atwar-dialog-body-${dialogSequence}`;
    head.querySelector('h2').id=titleId;body.id=bodyId;
    dialog.setAttribute('aria-labelledby',titleId);dialog.setAttribute('aria-describedby',bodyId);
    dialog.tabIndex=-1;
    const keydown=event=>{
      if(event.key==='Escape'){event.preventDefault();event.stopPropagation();cancel.click();return;}
      if(event.key!=='Tab')return;
      const focusable=[...dialog.querySelectorAll('button,input,select,textarea,a[href],[tabindex]')].filter(el=>!el.disabled&&el.tabIndex>=0&&!el.hidden&&el.getClientRects().length);
      if(!focusable.length){event.preventDefault();dialog.focus();return;}
      const first=focusable[0],last=focusable.at(-1),active=document.activeElement;
      if(event.shiftKey&&(active===first||!dialog.contains(active))){event.preventDefault();last.focus();}
      else if(!event.shiftKey&&(active===last||!dialog.contains(active))){event.preventDefault();first.focus();}
    };
    dialog.addEventListener('keydown',keydown);
    const initialTimer=setTimeout(()=>{if(dialog.isConnected){initialFocus.focus();if(['INPUT','TEXTAREA'].includes(initialFocus.tagName))initialFocus.select()}},0);
    return ()=>{if(--openDialogs===0)document.body.style.overflow=savedBodyOverflow;clearTimeout(initialTimer);dialog.removeEventListener('keydown',keydown);if(previous?.isConnected&&typeof previous.focus==='function')previous.focus({preventScroll:true});};
  }
  function confirmDialog({title='تأكيد الإجراء',message='',confirmText='تأكيد',cancelText='إلغاء',danger=false}={}){
    return new Promise(resolve=>{
      const backdrop=document.createElement('div');backdrop.className='atwar-dialog-backdrop';
      const dialog=document.createElement('section');dialog.className='atwar-dialog';dialog.setAttribute('role','dialog');dialog.setAttribute('aria-modal','true');
      const head=document.createElement('header');head.className='atwar-dialog-head';const h=document.createElement('h2');h.textContent=title;head.append(h);
      const body=document.createElement('div');body.className='atwar-dialog-body';body.textContent=message;
      const actions=document.createElement('footer');actions.className='atwar-dialog-actions';const ok=document.createElement('button'),cancel=document.createElement('button');ok.type=cancel.type='button';ok.className=`atwar-btn ${danger?'danger':'primary'}`;cancel.className='atwar-btn';ok.textContent=confirmText;cancel.textContent=cancelText;actions.append(ok,cancel);dialog.append(head,body,actions);backdrop.append(dialog);document.body.append(backdrop);
      const restore=prepareDialog(dialog,head,body,cancel,danger?cancel:ok);let settled=false;
      const done=value=>{if(settled)return;settled=true;backdrop.remove();restore();resolve(value)};ok.onclick=()=>done(true);cancel.onclick=()=>done(false);backdrop.onclick=e=>{if(e.target===backdrop)done(false)};
    });
  }
  function promptDialog({title='إدخال البيانات',message='',value='',placeholder='',confirmText='حفظ',cancelText='إلغاء',multiline=true,required=false}={}){
    return new Promise(resolve=>{
      const backdrop=document.createElement('div');backdrop.className='atwar-dialog-backdrop';
      const dialog=document.createElement('section');dialog.className='atwar-dialog';dialog.setAttribute('role','dialog');dialog.setAttribute('aria-modal','true');
      const head=document.createElement('header');head.className='atwar-dialog-head';const h=document.createElement('h2');h.textContent=title;head.append(h);
      const body=document.createElement('div');body.className='atwar-dialog-body';if(message){const p=document.createElement('p');p.textContent=message;body.append(p)}
      const input=document.createElement(multiline?'textarea':'input');input.className=multiline?'atwar-textarea':'atwar-input';input.value=String(value??'');input.placeholder=placeholder;input.setAttribute('aria-label',title);body.append(input);
      const validation=document.createElement('small');validation.setAttribute('aria-live','polite');validation.id=`atwar-prompt-validation-${dialogSequence+1}`;input.setAttribute('aria-describedby',validation.id);validation.style.cssText='display:block;color:var(--atwar-danger-600);margin-top:6px';body.append(validation);
      const actions=document.createElement('footer');actions.className='atwar-dialog-actions';const ok=document.createElement('button'),cancel=document.createElement('button');ok.type=cancel.type='button';ok.className='atwar-btn primary';cancel.className='atwar-btn';ok.textContent=confirmText;cancel.textContent=cancelText;actions.append(ok,cancel);dialog.append(head,body,actions);backdrop.append(dialog);document.body.append(backdrop);
      const restore=prepareDialog(dialog,head,body,cancel,input);let settled=false;
      const done=result=>{if(settled)return;settled=true;backdrop.remove();restore();resolve(result)};ok.onclick=()=>{const result=input.value.trim();if(required&&!result){validation.textContent='هذا الحقل مطلوب.';input.setAttribute('aria-invalid','true');input.focus();return}done(result)};cancel.onclick=()=>done(null);backdrop.onclick=e=>{if(e.target===backdrop)done(null)};input.oninput=()=>{input.removeAttribute('aria-invalid');validation.textContent=''};input.onkeydown=e=>{if(!multiline&&e.key==='Enter'){e.preventDefault();ok.click()}};
    });
  }
  window.AtwarUI=Object.freeze({toast,saveState,confirm:confirmDialog,prompt:promptDialog});
})();
