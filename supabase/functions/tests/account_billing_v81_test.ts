import { identityValues, appleSubject } from '../_shared/billing-identity.ts';
function assert(value: boolean) { if (!value) throw new Error('assertion failed'); }
Deno.test('再登録で内部IDが変わっても外部識別値を維持する',()=>{
  const first={identities:[{provider:'apple',identity_id:'internal1',id:'provider1',identity_data:{sub:'stable'}}]};
  const second={identities:[{provider:'apple',identity_id:'internal2',id:'provider1',identity_data:{sub:'stable'}}]};
  assert(identityValues(first).includes('apple:stable'));
  assert(identityValues(second).includes('apple:stable'));
  assert(identityValues(first).includes('apple:internal1'));
  assert(appleSubject(first.identities[0])==='stable');
});
Deno.test('未確認メールでは付与履歴を関連付けない',()=>{
  assert(!identityValues({email:'a@example.com'}).includes('email:a@example.com'));
  assert(identityValues({email:'A@EXAMPLE.COM',email_confirmed_at:'yes'}).includes('email:a@example.com'));
});
