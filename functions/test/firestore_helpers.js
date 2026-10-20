const {post,reverse}=require('../engine');const {doc,runTransaction,serverTimestamp,increment}=require('firebase/firestore');
const today=()=>new Date(Date.now()+5*3600000).toISOString().slice(0,10);
const blank=()=>({balances:{},obligations:{},unique:{},unallocated:{},closed:{},accounts:['cash','bank']});
const types=require('../types.json');const resolve=(s,e)=>s.replace(/\{(\w+)\}/g,(_,k)=>e[k]||'');
const meta=(e,uid='owner')=>({...e,definition:require('../../config/posting-types.json')[e.type],debitAccount:resolve(types[e.type].debit,e),creditAccount:resolve(types[e.type].credit,e),allocations:e.allocations||[],allocatedAmount:(e.allocations||[]).reduce((sum,a)=>sum+a.amount,0),reference:e.reference||'',createdBy:uid,createdAt:serverTimestamp()});
const stateDoc=(s,e,kind='post',original='',reversal='')=>({balances:Object.fromEntries(Object.entries(s.balances).filter(([k])=>!k.startsWith('money:'))),obligations:s.obligations,unique:s.unique,unallocated:s.unallocated||{},operation:Object.fromEntries(Object.entries(e).filter(([k])=>k!=='createdAt')),lastOperation:e.id,lastKind:kind,lastOriginal:original,lastReversal:reversal});
async function postDb(db,store,input,uid='owner',tamper){const type=types[input.type];return runTransaction(db,async t=>{
 const er=doc(db,`stores/${store}/entries/${input.id}`),sr=doc(db,`stores/${store}/modules/${type.module}`);
 if((await t.get(er)).exists())return {repeated:true};
 const ss=await t.get(sr),cs=await t.get(doc(db,`stores/${store}/control/periods`));
 const state={...blank(),...(ss.data()||{})};if(cs.exists()&&cs.data().lockedThrough)state.closed[cs.data().lockedThrough]={};
 const result=post(state,{date:today(),party:'person',account:'cash',target:'bank',reference:input.id,...input,allocations:input.allocations||[]},{role:'owner',active:true});
 if(input.orderId)await t.get(doc(db,`stores/${store}/orders/${input.orderId}`));
 const e=meta(result.entry,uid),next=stateDoc(result.state,e);if(tamper)tamper(e,next);
 t.set(sr,next);t.set(er,e);if(input.orderId)t.update(doc(db,`stores/${store}/orders/${input.orderId}`),{status:'received',billId:e.id,billAmount:e.amount,updatedBy:uid,updatedAt:serverTimestamp()});
 for(const [key,value] of Object.entries(e.effects).filter(([k,v])=>k.startsWith('money:')&&v!==0))t.set(doc(db,`stores/${store}/accounts/${key.slice(6)}`),{balance:increment(value),lastOperation:e.id,lastModule:e.module},{merge:true});return e;
});}
async function correctDb(db,store,originalId,replacement){return runTransaction(db,async t=>{
 const er=doc(db,`stores/${store}/entries/${replacement.id}`);if((await t.get(er)).exists())return;
 const or=doc(db,`stores/${store}/entries/${originalId}`),os=await t.get(or),original=os.data(),sr=doc(db,`stores/${store}/modules/expenses`),ss=await t.get(sr),control=await t.get(doc(db,`stores/${store}/control/periods`));
 const state={...blank(),...ss.data()};if(control.exists())state.closed[control.data().lockedThrough]={};
 const rid='reverse-'+replacement.id,reversed=reverse(state,original,{id:rid,date:today(),reason:'Correct expense'},{role:'owner',active:true});
 const posted=post(reversed.state,{date:today(),account:'cash',category:'Tea',...replacement,replaces:originalId,allocations:[]},{role:'owner',active:true}),e=meta(posted.entry);
 const rev={...reversed.entry,correctionReversal:true,debitAccount:original.creditAccount,creditAccount:original.debitAccount,allocations:original.allocations,allocatedAmount:original.allocatedAmount,advanceDelta:-original.advanceDelta,createdBy:'owner',createdAt:serverTimestamp()};
 t.set(sr,stateDoc(posted.state,e,'correct',originalId,rid));t.set(er,e);t.set(doc(db,`stores/${store}/entries/${rid}`),rev);t.update(or,{reversedBy:rid});
 const effects={...e.effects};for(const [k,n]of Object.entries(rev.effects))effects[k]=(effects[k]||0)+n;
 for(const [k,n]of Object.entries(effects))if(k.startsWith('money:')&&n!==0)t.set(doc(db,`stores/${store}/accounts/${k.slice(6)}`),{balance:increment(n),lastOperation:e.id,lastModule:e.module},{merge:true});
});}
async function reverseDb(db,store,originalId,id){return runTransaction(db,async t=>{
 const or=doc(db,`stores/${store}/entries/${originalId}`),original=(await t.get(or)).data(),sr=doc(db,`stores/${store}/modules/${original.module}`),ss=await t.get(sr);
 const result=reverse({...blank(),...ss.data()},original,{id,date:today(),reason:'Remove incorrect expense'},{role:'owner',active:true});
 const e={...result.entry,debitAccount:original.creditAccount,creditAccount:original.debitAccount,allocations:original.allocations,allocatedAmount:original.allocatedAmount,advanceDelta:-original.advanceDelta,createdBy:'owner',createdAt:serverTimestamp()};
 if(original.orderId)t.update(doc(db,`stores/${store}/orders/${original.orderId}`),{status:'open',billId:'',billAmount:0,updatedBy:'owner',updatedAt:serverTimestamp()});
 t.set(sr,stateDoc(result.state,e,'reverse',originalId,id));t.set(doc(db,`stores/${store}/entries/${id}`),e);t.update(or,{reversedBy:id});
 for(const [k,n]of Object.entries(e.effects))if(k.startsWith('money:')&&n!==0)t.set(doc(db,`stores/${store}/accounts/${k.slice(6)}`),{balance:increment(n),lastOperation:e.id,lastModule:e.module},{merge:true});
 });}
module.exports={postDb,correctDb,reverseDb,today};
