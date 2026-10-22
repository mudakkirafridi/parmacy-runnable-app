# Pharmacy Hisab 5.0.0 - Asaan entry aur Committee

## Rozana istemal
1. Home par New entry dabayein. Entry type mein Daily sale, Expense, Company bill, Ograi, Qarz, Salary, Committee ya Owner ki entry select karein. Usi form ke fields badal jate hain.
2. Naam khud select karein. Amount aur date likhein. Jahan paisa aata/jata hai wahan Cash ya Bank select karein, phir Save entry aur Save.
3. Naya naam: Add profile > Profile type select > naam. Staff mein salary aur Committee mein total, har qist, Daily/Weekly/Monthly schedule aur start date bhi dein.
4. Reports tab seedha All reports kholta hai. Upar Report dropdown se sirf Committee, Ograi, Qarz, Salary ya koi aur report nikalein. PDF share button maujood hai; specific reports ki picture bhi share ho sakti hai.
5. Committee qist dene ke liye Committee qist di; committee ka paisa milne par Committee raqam mili. Committee ki raqam milne se baqi dene wali qistain clear nahi hotin. Baqi qistain aur next date alag hain.
6. Entry par tap se Receipt, Edit aur Remove/reverse istemal kar sakte hain. Purani audited history barqarar rehti hai.

## Cash / Bank ka hisab
- Nayi Daily sale selected Cash/Bank mein jama hoti hai. Aik din ki sale aik hi entry hai; purane aur naye sale type ki duplicate date bhi roki jati hai.
- Qarz wosool, owner capital aur committee receipt selected account barhate hain.
- Expense/rent, Qarz dena, Ograi, salary, committee qist aur owner withdrawal selected account se minus hote hain.
- Company bill sirf payable barhata hai. Company return payable kam karta hai. In dono se khud cash nahi kat-ta; payment se kat-ta hai.
- Edit sirf farq adjust karti hai; reversal usi transaction ka actual account effect ulta karti hai. Salary pehle due clear karti hai, extra advance banta hai.
- Home ke cash/bank/current balances central ledger se hain. Daily sale/expenses selected din ke hain. Home par Qarz, company payable, salary remaining aur Committee ka hisab bhi hai.

## Purani app se update karte waqt zaroori
Purani Daily sale entries non-cash sale summaries thin; unhein silently cash receipts mein dobara nahi badla gaya. Update ke baad pehli dafa actual cash gin kar aur bank statement dekh kar Home > Set actual balance mein har account ki asal amount set karein. Sirf difference ka auditable adjustment save hota hai. Isay sale/income ki duplicate entry na banayein. Sab owners ke phones par naya version lagayein, kyun ke purana version sale ko cash receipt nahi banata.
App ko uninstall ya Clear data na karein; APK ko Update karein. Local entries/queue aur purana journal barqarar hain. Internet par automatic background sync wahi rehta hai.

## Committee check ki misal
Total 30,000 aur weekly qist 1,000. Do qistain dene se paid 2,000 aur qistain baqi 28,000. Agar committee 30,000 pehle mil jaye to bank/cash mein 30,000 aayega, lekin baqi dene wali qistain 28,000 hi rahengi. Reverse qist se payment aur schedule wapas durust hote hain. Monthly schedule month ke aakhri din ko sahi clamp karta hai; partial qist par next due date wahi rehti hai jab tak woh qist poori na ho.

## Verification
Flutter tests: see build manifest. Backend/rules tests 11 pass, including first committee entry without precreated module, account updates, edits/reversals and privacy. PDF sample render aur 360/430 pixel screens visually checked. Physical phone installation, real fingerprint aur native keyboard acceptance device par check karna baqi hai. Firebase Authentication/Firestore free Spark par hain; paid backend service add nahi ki.
