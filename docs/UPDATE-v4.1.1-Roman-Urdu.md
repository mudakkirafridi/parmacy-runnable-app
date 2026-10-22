# Pharmacy Hisab 4.1.1

Typing aur More screen update.

- Tamam 32 editable fields par autocorrect, suggestions, personalized keyboard learning aur smart punctuation band hain. Urdu composing/selection ko app rewrite nahi karti.
- Login email aur password ka keyboard raw visible-password variation use karta hai; password phir bhi chhupa rehta hai jab tak eye button na dabayein. Email mein @ aur . keyboard symbols se enter ho sakte hain. Vendor email-domain prediction ko request nahi kiya jata.
- Login inputs se be-asar formatter hata diya hai. App deleted text ko guess ya replace nahi karti. Controller text editing ke dauran dobara set nahi hota.
- More mein blue pharmacy card aur Preferences, Pharmacy, Records, Security & access groups hain. Purane actions aur permissions barqarar hain.

Phone par check:
1. Purani app uninstall kiye baghair nayi APK Update karein.
2. Email mein test@example.con likhein. n aur o backspace se hatayein, phir om likhein. Result test@example.com ho.
3. Password mein sample@178 likhein; 78 hata kar 2 likhein. Result sample@12 ho. Eye on/off dono mein check karein.
4. Ghalat login ke baad password khali ho. Email select-all karke replace karein; purani value wapas na aaye.
5. Cursor beech mein rakh kar, selection replace, paste, keyboard hide/show aur screen dobara khol kar bhi check karein.
6. Company/profile name, search, notes, amount, owner share aur PIN fields mein delete/retype karein. Urdu naam bhi type karein.
7. More screen light/dark aur Urdu mein kholein; cards, toggles aur scroll ke aakhir ke security actions check karein.

59 Flutter tests pass. IME state tests email suffix, password deletion/retyping, show/hide aur failed-login retry check karte hain. Screenshots light/dark/Urdu mein inspect kiye hain. Physical Android keyboard abhi test nahi hua; framework tests vendor keyboard ke stale native buffer ko reproduce nahi karte. Yeh update us behavior ke liye keyboard-mode mitigation hai, device par tasdeeq zaroori hai.
