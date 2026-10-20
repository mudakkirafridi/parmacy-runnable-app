# Pharmacy Hisab 4.0.0 - Manual check

Purani app par nayi APK ko Update karein. Uninstall ya Clear data na karein.

1. Email/password mein kuch likhein, aakhir ke do harf keyboard se mita kar naya harf likhein. Purane harf wapas nahin aane chahiye. Beech mein cursor, select-all, paste aur keyboard delete bhi check karein. Ghalat login ke baad password khaali ho; dobara typing sahi ho. Samsung keyboard aur Gboard dono par check karein.
2. App band karke PIN se kholein. Ghalat PIN ke baad field saaf ho. Sahi 4-digit PIN aur Unlock se khule. Registered fingerprint bhi check karein.
3. Home par Pay company / Ograi aur Owner withdrawal kholein. Owner, amount aur date select karke entry karein. Cashbook aur owner report mein aik hi entry aaye.
4. Companies mein naya bill kholein. Bill number 1 se shuru ho; agla numeric number khud aaye. Number edit karein; due date na ho. Order se bill kholne par bhi number aaye.
5. Net daily sale mein calendar se purani khuli date select karein. Report mein sirf asal entry date aaye. Band date ki entry reject honi chahiye.
6. Qarz wosool mein naam badlein. Har shakhs ka apna baqaya foran nazar aaye.
7. Pay salary mein staff select karein. Remaining salary aur advance dikhe. Allocate to bill na ho. Normal salary purane salary periods mein khud allocate ho. Advance dene ke liye isi screen ka Pay advance switch use karein. Add entry menu mein alag advance/apply advance na ho.
8. Profiles ke upar Add profile se category chun kar naam save karein. Airplane mode mein company/profile aur order save karke app band/kholein: record aur pending upload baqi rehna chahiye. Internet on karke More > uploads/refresh dabayein. Doosre device par record aik martaba aaye.
9. Balance wale profile ko delete karein: baqaya loan/salary/advance nazar aaye. Clear balance ya Force move to bin chun sakein. Recycle bin se Restore karein. Dobara bin mein bhej kar Delete permanently karein. Profile app/bin se hat jaye; purani reports aur balances barqarar rahein. Database mein visible=0/1; permanent removal hidden purged tombstone rakhta hai taake history ka naam na khoye.
10. Expense ki amount/category edit karein. Reason field na ho. Purani entry reverse aur nayi amount ka sirf aik asar ho. Duplicate entry reverse karein; reason field na ho. Paid bill ko reverse karne se pehle linked payment/return reverse karna zaroori hai.
11. Reports > Pay company / Ograi mein aik company chunain. 50,000 bill aur 10,000 payment par Before 50,000 / Paid 10,000 / Remaining 40,000 aaye. Doosri 10,000 payment par 40,000 / 10,000 / 30,000 aaye. 5,000 confirmed return par Return 5,000 / Remaining 25,000 aaye. Return reverse ho to 30,000 rahe.
12. Company bills, all reports, Qarz PDF aur picture share karke dekhein. Name/company bold; amount aur entry date saaf hon. Negative balance red ho. Bara report multiple pages mein mukammal ho.

Local SQLite cache aur durable upload queue profiles/companies aur orders ke liye hai. Financial entries server validation ke baad post hoti hain; internet na ho to Save local draft use karein. Free Firebase/Firestore use hota hai; paid Functions ya Blaze ki zaroorat nahin.

Automated checks physical Samsung keyboard, fingerprint aur real-device sharing ka badal nahin hain.
