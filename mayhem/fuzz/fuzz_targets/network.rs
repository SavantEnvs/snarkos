#![no_main]
use libfuzzer_sys::fuzz_target;
use bytes::BytesMut;
use tokio_util::codec::Decoder;
use tokio_util::codec::LengthDelimitedCodec;

fuzz_target!(|data: &[u8]| {
    // Fuzz the length-delimited framing layer used by snarkOS network messages
    let mut codec = LengthDelimitedCodec::builder()
        .max_frame_length(128 * 1024 * 1024)
        .new_codec();
    let mut bytes = BytesMut::from(data);
    while let Ok(Some(frame)) = codec.decode(&mut bytes) {
        // Attempt to parse the message ID and basic fields
        let _ = parse_message(frame.into());
    }
});

fn parse_message(mut bytes: bytes::Bytes) -> Option<()> {
    use bytes::Buf;
    if bytes.remaining() < 2 {
        return None;
    }
    let id = bytes.get_u16_le();
    match id {
        0 => {}, // Ping: no data
        1 | 2 => {
            // Pong(u32) or BlockRequest(u32)
            let _: u32 = bincode::deserialize(&bytes).ok()?;
        }
        3..=5 => {}, // BlockResponse, TransactionBroadcast, BlockBroadcast: raw bytes
        _ => {},
    }
    Some(())
}
