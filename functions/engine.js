const types = require('./types.json');
const fail = message => { throw new Error(message); };
const safe = n => Number.isSafeInteger(n) && n >= 0 && n <= 900000000000;
const key = s => typeof s === 'string' && /^[a-zA-Z0-9_\- .]{1,100}$/.test(s);
function authorize(member, module, action='post') {
 if (!member || !member.active) fail('Access revoked or no store membership');
 if(member.role==='owner') return;
 if(module==='owner' || action==='owner') fail('Owner approval required');
 if(member.role==='manager' && !['salary','zakat','zakat_companies','loans','committee'].includes(module)) return;
 if(!(member.permissions||[]).includes(`${module}:${action}`)) fail('Module permission required');
}
function post(previous, input, member) {
 const s=structuredClone(previous); s.balances||={};s.obligations||={};s.unique||={};s.closed||={};
 const x=structuredClone(input), type=types[x.type];
 if(!type) fail('Unknown transaction');if(type.retired)fail('This entry type has been removed; use Profiles or the current register'); authorize(member,type.module,type.owner?'owner':'post');
 if(!key(x.id)||!/^\d{4}-\d{2}-\d{2}$/.test(x.date)||Number.isNaN(Date.parse(x.date))||new Date(x.date).toISOString().slice(0,10)!==x.date) fail('Invalid operation ID or date');
 if(Object.keys(s.closed).some(d=>d>=x.date)) fail('Day is closed. Use owner reversal on an open date.');
 if(!safe(x.amount)||(!type.allowZero&&x.amount<=0)) fail('Enter a positive amount in paisa');
 for(const f of ['party','account','target','category']) if(x[f]&&!key(x[f])) fail(`Invalid ${f}`);
 if(((type.debit+type.credit).includes('{party}')||type.partyRequired) && !x.party) fail('Select a person or supplier');
 const accounts=s.accounts||['cash','bank'];
 if((type.debit+type.credit).includes('{account}') && !accounts.includes(x.account)) fail('Unknown payment account');
 if(x.type==='transfer' && (!accounts.includes(x.target)||x.target===x.account)) fail('Choose a different destination account');
 if(x.type==='expense' && !x.category) fail('Expense category required');
 if(x.due && (!/^\d{4}-\d{2}-\d{2}$/.test(x.due)||Number.isNaN(Date.parse(x.due))))fail('Invalid due date');
 if(x.type==='salary_accrual' && x.salaryCalculation){const c=x.salaryCalculation;if(!safe(c.rate)||!Number.isInteger(c.days)||c.days<=0||!safe(c.allowance)||!safe(c.deduction)||!['Daily','Weekly','Monthly'].includes(c.basis))fail('Invalid salary calculation');if(c.deduction>0&&!c.deductionReason?.trim())fail('Deduction reason required');const d=new Date(x.date);const divisor=c.basis==='Monthly'?(c.proration==='Fixed 30 days'?30:new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+1,0)).getUTCDate()):c.basis==='Weekly'?7:1;const earned=Math.floor((c.rate*c.days+Math.floor(divisor/2))/divisor)+c.allowance-c.deduction;if(earned!==x.amount)fail('Salary calculation differs from submitted amount');}
 if(type.onePerDay&&['cash','bank','returns','refundCash','refundBank','retained','credits','reductions'].some(k=>x[k]!==undefined))fail('Enter only the net daily sale from Abuzar');
 if(type.period&&!x.reference) fail('Unique period or shift reference required');
 if(type.obligation&&!x.reference) fail('Bill/period reference required');
 const unique=type.onePerDay?`daily_sales:${x.date}`:(type.obligation||type.period)?`${x.type}:${x.party||''}:${x.type==='daily_sales'?x.date+':':''}${x.reference}`:null;
 if(unique && s.unique[unique]) fail('This bill or period is already posted');
 if(unique)s.unique[unique]=x.id;
 const effects={}; const add=(a,n)=>effects[a]=(effects[a]||0)+n;
 const resolve=t=>t.replace(/\{(\w+)\}/g,(_,k)=>x[k]||'');
 const debit=resolve(type.debit),credit=resolve(type.credit);
 add(debit,x.amount);add(credit,-x.amount);
 if(type.limit) {
  const a=['customer_collection','writeoff'].includes(x.type)?credit:x.type==='loan_collect'?credit:debit;
  const available=x.type==='loan_repay'?-(s.balances[a]||0):(s.balances[a]||0);
  if(x.amount>available && !(x.type==='customer_collection' && x.allowAdvance===true))fail('Amount exceeds outstanding; customer advance must be explicit');
 }
 if(type.requireCredit){ const a=x.type==='supplier_refund'?credit:debit; const available=(s.balances[a]||0)*(x.type==='supplier_refund'?1:-1);if(x.amount>available)fail('Refund exceeds available credit'); }
 if(x.type==='salary_apply' && x.amount>(s.balances[credit]||0))fail('Advance balance insufficient');
 const allocations=x.allocations||[];let allocated=0;
 if(allocations.length&&!type.allocate)fail('This entry cannot allocate bills');
 for(const a of allocations){const b=s.obligations[a.id];if(!b||b.party!==x.party||b.module!==type.module||!safe(a.amount)||a.amount<=0)fail('Invalid allocation');if(!type.creditReturn&&a.amount>b.remaining)fail('Allocation exceeds outstanding balance');b.remaining-=a.amount;allocated+=a.amount;}
 if(allocated>x.amount)fail('Allocation exceeds payment');
 if(type.allocate&&allocated<x.amount&&!type.creditReturn&&!x.allowAdvance)fail('Allocate payment or explicitly mark unallocated advance');
 if((x.type==='salary_apply'||type.applyCredit)&&allocated!==x.amount)fail('Allocate entire advance to a salary period');
 const unallocated=s.unallocated||=( {} );const advanceKey='supplier:'+(x.party||''),available=unallocated[advanceKey]||0;
 const advanceDelta=['supplier_payment','supplier_return'].includes(x.type)?x.amount-allocated:x.type==='supplier_apply'?-x.amount:x.type==='supplier_refund'?-Math.min(x.amount,available):0;
 if(available+advanceDelta<0)fail('Unallocated advance insufficient');if(advanceDelta!==0)unallocated[advanceKey]=available+advanceDelta;x.advanceDelta=advanceDelta;
 if(type.obligation){s.obligations[x.id]={id:x.id,party:x.party,module:type.module,reference:x.reference,original:x.amount,remaining:x.amount,date:x.date,due:x.due||x.date};}
 if(Object.values(effects).reduce((a,b)=>a+b,0)!==0)fail('Unbalanced entry');
 for(const [a,n] of Object.entries(effects)){s.balances[a]=(s.balances[a]||0)+n;if(!Number.isSafeInteger(s.balances[a]))fail('Balance out of range');}
 return {state:s,entry:{...x,module:type.module,effects,unique,status:'posted'}};
}
function reverse(previous, original, input, member) {
 authorize(member,original.module,'owner');if(!input.reason?.trim())fail('Correction reason required');
 if(!/^\d{4}-\d{2}-\d{2}$/.test(input.date)||Number.isNaN(Date.parse(input.date)))fail('Correction date required');
 const s=structuredClone(previous);if(Object.keys(s.closed).some(d=>d>=input.date))fail('Use an open correction date');
 if(original.status!=='posted'||original.reversedBy||original.type==='reversal')fail('Entry cannot be reversed');
 const own=s.obligations[original.id];if(own && own.remaining!==own.original)fail('Reverse linked allocations first');
 delete s.obligations[original.id];
 for(const a of original.allocations||[]) {if(!s.obligations[a.id])fail('Linked bill missing');s.obligations[a.id].remaining+=a.amount;}
 const effects={};for(const [a,n] of Object.entries(original.effects)){effects[a]=-n;s.balances[a]=(s.balances[a]||0)-n;}
 const advanceKey='supplier:'+(original.party||''),delta=original.advanceDelta||0;s.unallocated||={};if(delta!==0){if((s.unallocated[advanceKey]||0)-delta<0)fail('Reverse linked advance applications first');s.unallocated[advanceKey]=(s.unallocated[advanceKey]||0)-delta;}
 if(original.unique) delete s.unique[original.unique];
 return {state:s,entry:{id:input.id,type:'reversal',module:original.module,date:input.date,amount:original.amount,party:original.party||'',reference:original.id,reason:input.reason,effects,status:'posted'}};
}
module.exports={types,post,reverse,authorize};
