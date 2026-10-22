# Pharmacy Hisab 5.1.0

- Home: New entry aur New profile. Bottom tabs: Home, Reports, More.
- Registers aur Quick entry menus hata diye gaye hain. Purane statement routes compatibility ke liye internal hain.
- Financial names English / Urdu dono mein ek jaisay hain; user ke profile names nahi badlay.
- Installment report mein Balance, Paid, Received, Remaining aur Date hain. PDF/picture ascending dates rakhte hain.
- App reports latest date pehle, aur har date par Today/Yesterday/weekday heading. Exports mein weekday headings nahi.
- New entry form type ke mutabiq icon, rang aur fields badalta hai.
- Roman Urdu PDF guide: docs/Pharmacy-Hisab-Guide-v5.1-Roman-Urdu.pdf.

Validation: 86 Flutter tests passed, flutter analyze clean. Existing backend/rules unchanged from v5.0. Physical Android keyboard/fingerprint acceptance device par karein.

Purani daily sales non-cash summaries thi. Asal cash aur bank counted balance se ek dafa verify/set karein; purani sales dobara enter na karein. Update install karein; uninstall/clear data na karein.
