const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
test('active client and reference engine share exactly the same type definitions',()=>{assert.deepEqual(JSON.parse(fs.readFileSync('../assets/transaction_types.json','utf8')),require('../types.json'));});
