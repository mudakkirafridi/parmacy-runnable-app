# Pharmacy Hisab 4.3.0

## Is update mein
- Ograi mein aik company ke aik din ke bills ka total sirf us din ki pehli row par hai. App mein latest date pehle; PDF/picture pehle wale chronological order mein hain.
- Home company se Pay company / Ograi aur usi company ka Ograi report khulta hai.
- Home cash, bank, Qarz aur company payable poori pharmacy ke current balances hain. Daily sale aur expenses selected din ke hain.
- All reports ke summary mein sirf poori pharmacy ka Qarz baqaya, remaining salary aur remaining company payments hain.
- Email/password ke neeche Set / reset PIN se 4-digit PIN bana sakte hain. First login mein PIN zaroori hai; Forgot PIN par valid email/password ke baad yahin naya PIN save hota hai. Normal unlock page wahi hai.
- Daily sale edit ke baad naam Net daily sale hi rehta hai.
- Naye entry forms company/person/staff khud select nahi karte. Company ke form mein Select company, salary mein Select staff hai. Company card se payment kholne par wahi company selected hoti hai.
- Register aur report entries app mein latest date pehle dikhati hain; PDFs aur pictures ka order nahi badla.

## Phone par manual check
1. Existing app uninstall/Clear data kiye baghair APK ko Update karein.
2. Home ki date purani karein: cash/bank/Qarz/company balances wohi rahein; sale/expenses us din ke hon.
3. Company card par tap karke Ograi report kholein. Aik date ki multiple payment/return rows mein Day bills sirf pehli row mein hon. PDF/picture chronological hon.
4. First login ya Forgot PIN par email/password aur matching 4-digit PIN login page par save karein. Wrong password se PIN reset na ho. App band/khol kar pehle wali unlock screen par PIN aur available fingerprint check karein.
5. Fresh company bill/payment, salary aur Qarz form mein khud person select karein. Home company ke payment mein selected company barqarar ho.
6. Daily sale ko edit karein: amount update ho aur naam Net daily sale ho.
7. All reports ki period date badlein: global remaining totals wohi rahein, table filter ke mutabiq badle.
8. Email/password mein characters delete karke dobara likhein; purana deleted text wapas na aaye. Is update mein existing native Android credential fix barqarar hai.

## Verification
72 Flutter tests pass; analyzer clean. New tests PIN setup/reset, wrong password protection, blank selections, all-time Home/report balances, sale edit label aur app/export date order cover karte hain. Android release compile/signing verify ki gayi hai. Physical device, native keyboard aur real fingerprint acceptance user device par baqi hai.
Firebase free Spark, Authentication aur Firestore setup barqarar hai. Is release mein rules/backend ko badla ya production journal ko tooling se modify nahi kiya gaya.
