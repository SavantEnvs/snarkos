#![no_main]
use libfuzzer_sys::fuzz_target;
use bytes::{Buf, BytesMut};

/// Replicate snarkOS Message::deserialize for fuzzing without the snarkOS/snarkVM dependencies.
fn deserialize_message(mut bytes: BytesMut) -> Option<()> {
    if bytes.remaining() < 2 {
        return None;
    }
    let id = bytes.get_u16_le();
    match id {
        0 => {
            if !bytes.is_empty() {
                return None;
            }
        }
        1 | 2 => {
            // Pong(u32) or BlockRequest(u32) via bincode
            let _: u32 = bincode::deserialize(&bytes).ok()?;
        }
        3 | 4 | 5 => {
            // BlockResponse / TransactionBroadcast / BlockBroadcast: keep as raw buffer
        }
        _ => return None,
    }
    Some(())
}

fuzz_target!(|data: &[u8]| {
    let bytes = BytesMut::from(data);
    let _ = deserialize_message(bytes);
});
