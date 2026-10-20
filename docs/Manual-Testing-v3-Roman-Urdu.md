# Pharmacy Hisab 3.0.3 - Roman Urdu

Pharmacy-Hisab-v3.0.3-Editing-Fix.apk ko purani app par Update install karein. Uninstall/Clear data na karein. Purana data aur PIN barqarar hain.

## Back aur PIN

Phone Back se ek step peechhe jayega: New order dialog > Orders > Registers > Home. Home par do Back taps (2 seconds mein) app close karte hain. Keyboard/dialog khula ho to pehla Back usay band kar sakta hai. Entry save hone par bhi caller screen par wapas aata hai.

4-digit PIN enter karke Unlock dabayein. Field ke cross icons hata diye hain. PIN keypad ka delete key rehta hai. More > PIN & fingerprint se fingerprint enable karein; phone mein fingerprint enrolled hona chahiye.

## Email aur password

Cross icons hata diye hain; keyboard Backspace/Select all se edit karein. Password eye se show/hide hota hai. Wrong password clear hota hai. Suggestions, personalized learning aur autofill is form par band hain; failure ke baad nayi editing session banti hai, taake old wrong text wapas insert na ho.

## Qarz

Sirf do actions hain: Qarz (pharmacy se raqam di), Qarz wosool (pharmacy ko raqam mili). Staff ki di hui raqam bhi Qarz wosool mein enter kar sakte hain, chahe pehle Qarz entry na ho. Qarz liya/borrow aur repay menus hata diye hain. Purani financial history delete nahi hoti.

Baqaya wo net raqam hai jo person se leni hai. Jama wo net raqam hai jo extra pharmacy ko mili hai. Person-wise PDF/picture mein Date, Lena hai, Dena hai aur aakhri signed Net balance hai. Reverse row negative amount se correction dikhati hai. Kisi aur person ki details personal statement mein nahi aati.

## Rent aur Orders

Rent ka alag register/profile/report menu hata diya hai. Nayi rent entry: Expenses > Record expense > Category Rent. Purani rent history All reports aur Expense reports mein rehti hai.

Orders: company dropdown, order dene wale ka naam, amount. Staff salary profile lazmi nahi. Bill received se actual company bill link hota hai.

## Reverse

Entry kholein > Remove / reverse entry > reason > Confirm reversal. Zakat, expense, salary advance aur Qarz ke missing-cash-balance error ko fix kiya gaya hai. Reverse history delete nahi karta; inverse entry balance correct karti hai. Paid supplier bills ke linked payments/returns pehle reverse karne padte hain. Salary mein apply hua advance bhi pehle unapply/reverse hota hai. Closed dates par correction open date par hoti hai.

## Checks

46 Flutter tests aur 10 backend/Firestore emulator tests pass. Naye receipt rules free Firebase par deploy hain. App update sab phones par install karein; old client ka loan-collection definition ab purana hai. Actual Samsung keyboard/fingerprint, phone update/reboot aur native sharing ka physical acceptance abhi baqi hai. Samples sirf SAMPLE data hain.


## 3.0.3 updates

Headings wrap at the available screen width with an adaptive toolbar height. Confirmed return credit is fully visible on a 360px phone. Owner share inputs accept 45, 45.0, 45.00 and 45.; total must still be 100. Owner edits show errors inside the form and update the cache after the server acknowledges the save, even when a later refresh is slow. 45/45/10 was tested in the form and real Firestore emulator, without changing real production owners.

Email/password/PIN and percentage inputs guard against a keyboard restoring deleted trailing characters. The exact abbas@178 -> abbas@1 -> stale abbas@1782 input sequence produces abbas@12. Normal middle insertion and ordinary paste are covered. Actual Samsung keyboard acceptance still needs a physical phone.

Report exports print no filter date range or generated date. Transaction dates remain in the rows. A personal loan statement shows Date, Lena hai, Dena hai and a single signed Net balance at the end; negative values are red in both PDF and PNG. All-person loan statements retain a Name column. Dates and balances are still filtered/calculated by the selected reporting period; earlier history contributes to the final balance. SAMPLE documents are synthetic.
