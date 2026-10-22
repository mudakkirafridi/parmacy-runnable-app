const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
test('cash sale and committee are validated by live Firestore rules, cash accounts and correction rules',{skip:!process.env.FIRESTORE_EMULATOR_HOST},async()=>{
 const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');const {doc,setDoc,getDoc}=require('firebase/firestore');const {postDb,reverseDb,editDb,today}=require('./firestore_helpers');
 const env=await initializeTestEnvironment({projectId:'demo-pharmacy-v50',firestore:{rules:fs.readFileSync('../firestore.rules','utf8')}});const store='shop';await env.clearFirestore();
 try{
 await env.withSecurityRulesDisabled(async c=>{const db=c.firestore();await setDoc(doc(db,'system/postingTypes'),JSON.parse(fs.readFileSync('../config/posting-types.json','utf8')));await setDoc(doc(db,`stores/${store}`),{name:'Test',accounts:['cash','bank']});await setDoc(doc(db,`stores/${store}/control/periods`),{lockedThrough:''});for(const role of ['owner','manager'])await setDoc(doc(db,`stores/${store}/members/${role}`),{role,active:true,permissions:[]});for(const m of ['sales','cashbook'])await setDoc(doc(db,`stores/${store}/modules/${m}`),{balances:{},obligations:{},unique:{},unallocated:{},lastOperation:'',lastKind:'',lastOriginal:'',lastReversal:''});for(const a of ['cash','bank'])await setDoc(doc(db,`stores/${store}/accounts/${a}`),{balance:0,lastOperation:'',lastModule:''});});
 const db=env.authenticatedContext('owner').firestore(),manager=env.authenticatedContext('manager').firestore();
 await assertSucceeds(setDoc(doc(db,`stores/${store}/profiles/committee`),{id:'committee',module:'committee',name:'Committee A',totalAmount:3000000,installmentAmount:1000000,frequency:'Monthly',startDate:today(),active:true,visible:1}));
 await assertFails(getDoc(doc(manager,`stores/${store}/profiles/committee`)));
 await assertSucceeds(postDb(db,store,{id:'new-sale',type:'daily_sale_cash',amount:1000000,account:'bank',party:''}));
 assert.equal((await getDoc(doc(db,`stores/${store}/accounts/bank`))).data().balance,1000000);
 await assert.rejects(postDb(db,store,{id:'duplicate-old-sale',type:'daily_sales',amount:1}),/already posted/);
 await assertSucceeds(editDb(db,store,'new-sale',{id:'sale-edit',type:'daily_sale_cash',amount:500000,account:'bank',party:''}));
 assert.equal((await getDoc(doc(db,`stores/${store}/accounts/bank`))).data().balance,500000);
 await assertSucceeds(reverseDb(db,store,'sale-edit','undo-sale'));assert.equal((await getDoc(doc(db,`stores/${store}/accounts/bank`))).data().balance,0);
 await assertSucceeds(postDb(db,store,{id:'qist',type:'committee_pay',amount:100000,party:'committee',account:'cash'}));
 await assertSucceeds(postDb(db,store,{id:'payout',type:'committee_receive',amount:3000000,party:'committee',account:'bank'}));
 assert.equal((await getDoc(doc(db,`stores/${store}/accounts/cash`))).data().balance,-100000);assert.equal((await getDoc(doc(db,`stores/${store}/accounts/bank`))).data().balance,3000000);
 await assertSucceeds(editDb(db,store,'qist',{id:'qist-edit',type:'committee_pay',amount:50000,party:'committee',account:'cash'}));
 assert.equal((await getDoc(doc(db,`stores/${store}/accounts/cash`))).data().balance,-50000);
 await assertSucceeds(reverseDb(db,store,'qist-edit','undo-qist'));assert.equal((await getDoc(doc(db,`stores/${store}/accounts/cash`))).data().balance,0);
 await assertSucceeds(postDb(db,store,{id:'actual-balance',type:'balance_in',amount:200000,account:'cash',party:''}));
 await assertSucceeds(reverseDb(db,store,'actual-balance','undo-balance'));assert.equal((await getDoc(doc(db,`stores/${store}/accounts/cash`))).data().balance,0);
 await assertFails(postDb(manager,store,{id:'forbidden-qist',type:'committee_pay',amount:50000,party:'committee',account:'cash'},'manager'));
 }finally{await env.cleanup();}
});
