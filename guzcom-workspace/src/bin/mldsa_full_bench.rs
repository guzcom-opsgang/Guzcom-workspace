use std::time::Instant;
use blake3::Hasher;
use fips204::ml_dsa_87::{PublicKey, PrivateKey};
use fips204::traits::{SerDes, Signer, Verifier};

fn main() {
    let pub_key = PublicKey::try_from_bytes([0u8; 2592]).unwrap();
    let priv_key = PrivateKey::try_from_bytes([0u8; 4896]).unwrap();
    let mut payload = [0u8; 8192];
    payload[0..4].copy_from_slice(&[0xDE, 0xAD, 0xBE, 0xEF]);
    
    let mut hasher = Hasher::new();
    hasher.update(&payload);
    let msg = hasher.finalize().as_bytes().to_vec();
    
    println!("operation,iteration,latency_ns");
    for i in 0..100 {
        let start = Instant::now();
        let _ = priv_key.try_sign(&msg, b"").ok();
        println!("sign,{},{}", i, start.elapsed().as_nanos());
    }
    
    let sig = priv_key.try_sign(&msg, b"").unwrap();
    for i in 0..100 {
        let start = Instant::now();
        let _ = pub_key.verify(&msg, &sig, b"");
        println!("verify,{},{}", i, start.elapsed().as_nanos());
    }
}
