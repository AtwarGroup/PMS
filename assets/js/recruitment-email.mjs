export async function sendRecruitmentEmail(sb,offerId,event,token=null){
 try{
 const {data,error}=await sb.functions.invoke('recruitment-email',{body:{offer_id:offerId,event,token}});
 if(error){let message='تعذر إرسال البريد. الإجراء محفوظ داخل النظام ويمكن إعادة المحاولة.';try{const detail=await error.context?.json();if(detail?.error)message=detail.error;}catch{}return {sent:false,message};}
 return {sent:!!data?.sent,pending:!!data?.pending,message:data?.sent?'تم إرسال نسخة البريد.':data?.pending?'طلب الإرسال قيد المعالجة.':data?.error||'لم يتأكد إرسال البريد.'};
 }catch{return {sent:false,message:'تعذر الاتصال بخدمة البريد. الإجراء محفوظ داخل النظام.'};}
}
