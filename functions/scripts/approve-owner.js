// Run only in a trusted admin environment with application-default credentials.
const {initializeApp,applicationDefault}=require('firebase-admin/app');
const {getAuth}=require('firebase-admin/auth');
initializeApp({credential:applicationDefault()});
const uid=process.argv[2];if(!uid)throw Error('Usage: node scripts/approve-owner.js AUTH_UID [revoke]');
(async()=>{const auth=getAuth(),user=await auth.getUser(uid);await auth.setCustomUserClaims(uid,{...(user.customClaims||{}),canCreateStore:process.argv[3]!=='revoke'});console.log('Bootstrap owner claim updated; sign out and in to refresh token.');})();
