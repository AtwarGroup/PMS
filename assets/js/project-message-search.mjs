import {historyQuery,historyPage,mergeHistory} from './project-history.mjs?v=2.5.57';
export function messageSearchQuery(sb,projectId,text,cursor=null){
 const term=String(text||'').trim().slice(0,200);
 if(!term)throw new TypeError('Search text required');
 return historyQuery(sb,'project_messages',projectId,cursor).ilike('body','%'+term.replace(/[\\%_]/g,c=>'\\'+c)+'%');
}
export function createMessageSearch({sb,projectId,render}){
 let epoch=0,text='',rows=[],cursor=null,more=false,busy=false;
 async function search(value,older=false){
  if(older&&(busy||!more))return;
  const token=older?epoch:++epoch;
  if(!older){text=String(value||'').trim().slice(0,200);rows=[];cursor=null;more=false;}
  if(!text){busy=false;render({rows:[],more:false,busy:false,text});return;}
  busy=true;render({rows,more,busy,text});
  try{
   const {data,error}=await messageSearchQuery(sb,projectId,text,older?cursor:null);
   if(token!==epoch)return;if(error)throw error;
   const page=historyPage(data);rows=mergeHistory(older?rows:[],page.rows).reverse();more=page.more;cursor=page.cursor;busy=false;
   render({rows,more,busy,text});
  }catch(error){if(token!==epoch)return;busy=false;render({rows,more,busy,text,error:'تعذر البحث. أعد المحاولة.'});}
 }
 return {search:value=>search(value),older:()=>search(text,true),cancel:()=>{epoch++;busy=false;}};
}
