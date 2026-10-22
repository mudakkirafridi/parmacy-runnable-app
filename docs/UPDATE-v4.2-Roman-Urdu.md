# Pharmacy Hisab 4.2.0

## Kya badla
- Salary payment pehle remaining salary clear karti hai; bachi raqam advance banti hai. 5,000 baqaya par 10,000 payment: outstanding 0, advance 5,000. Pay advance ka alag switch hata diya hai. Form mein current aur payment ke baad ki salary/advance dono hain.
- Purane records mein salary aur advance aik sath ho to balance net karke dikhaya jata hai. Agli salary payment par pehle purana advance non-cash apply hota hai. Purane journal records ko silently dobara nahi likha jata.
- Home ke end par All bills ki jagah Companies aur unka current remaining balance hai. Company par tap: Pay company / Ograi ya combined Company report (bills, payment, return).
- Ograi report mein Day bills usi company aur usi date ke active bills ka sum hai. Reverse hue bills is sum se bahar hain.
- Active entry ke detail mein Receipt, Edit, Remove / reverse entry hain. Edit se amount/date/name/account/reference/notes badal sakte hain; expense category bhi. Bill/period ke baki input metadata barqarar rehta hai.
- Edit purani entry ka audited inverse aur corrected replacement banata hai; ordinary statement mein sirf current version dikhai deti hai. Previous version se history khulti hai. Balance par sirf difference lagta hai.
- Reversed entry red hai aur View reversal / Original entry links hain. Dobara reversed entry ko reverse/edit nahi kiya ja sakta. Lambi internal IDs aur login UID ab detail sheet ko nahi torte.
- Multiple-bill payment Edit ko Firestore rule limit ke liye do validated server steps mein sync kiya jata hai. Local save aik atomic snapshot/queue write hai; interruption ke baad stable IDs aur editTarget se wahi edit resume hota hai. Kisi doosre remove/edit ka reversal reuse nahi hota.
- Paid/allocated bill ko edit ya reverse karne se pehle uski linked payments/returns reverse karni hoti hain. Closed date par open correction date select karein. Yeh balance safety checks hain.
- Android login email/password ab native EditText use karte hain. Native typing/delete ko controller se setText wapas nahi bheja jata. Explicit clear ke version badalte hain, is liye purane delayed input events cleared password ko wapas nahi la sakte. Eye toggle input type/buffer ko reset nahi karta. Password disk par save nahi hota.

## Phone par check
1. Purani app uninstall ya Clear data kiye baghair APK ko Update karein.
2. Password mein sample@321 likhein; 321 delete karke sirf 1 likhein. Result sample@1 ho. Eye on/off, middle cursor aur select-all replace ke sath check karein.
3. Email mein test@example.con se n aur o delete kar ke om likhein: test@example.com. Wrong login ke baad password blank aur email editable hon.
4. Staff ke 5,000 due par 10,000 salary pay karein; outstanding 0 aur advance 5,000 hon. Cash sirf 10,000 kam ho.
5. Home company card se Ograi aur combined report kholein. Company bill report mein manually reversed bill red ho.
6. Loan/expense/sale/payment ko 10,000 se 5,000 edit karein; current row 5,000 aur balance ka farq 5,000 ho. Previous version bhi khule. Nayi entry ko phir reverse karke balance verify karein.
7. Multiple-bill payment edit ke waqt internet band/on aur app restart karke pending queue ko resume hone dein. Duplicate cash/payment na ho. Agar server conflict par review banner aaye to usay resolve karein.
8. Salary, loan, company aur cashbook reports mein active entry ke Edit/Reverse options aur already reversed entries ke red status check karein.

## Verification
65 Flutter tests, 10 backend tests pass; analyzer clean.
Flutter IME bridge tests native edits ke echo, delayed old-buffer rejection, clear/retype aur existing fallback login flow ko cover karte hain. Native Android code release APK mein compile hua. Physical Samsung/Gboard, real fingerprint aur phone installation acceptance abhi user device par baqi hai.
Firestore emulator tests ordinary/linked bills, salary split, loan/sale/payment edits, three-bill interruption/retry, duplicate prevention, staff edit denial aur forged correction rejection cover karte hain. Production journal entries ko tooling se modify nahi kiya gaya. Free Spark Firestore/Authentication setup barqarar hai.
