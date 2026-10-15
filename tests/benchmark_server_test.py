"""Checks packet accounting, especially loopback duplicates and protocol headers."""
import importlib.util
from pathlib import Path
import socket
import struct
import unittest

spec = importlib.util.spec_from_file_location("benchmark", Path(__file__).parents[1] / "tools/benchmark_server.py")
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


class PacketAccountingTest(unittest.TestCase):
    def frame(self, source=24683, options=0):
        header = 20 + options
        ip = bytearray(header + 12)
        ip[0] = 0x40 | (header // 4)
        struct.pack_into("!H", ip, 2, len(ip))
        ip[9] = 17
        ip[12:20] = b"\x7f\x00\x00\x01" * 2
        struct.pack_into("!HHHH", ip, header, source, 40000, 12, 0)
        return b"\0" * 12 + b"\x08\x00" + ip

    def test_headers_and_ip_options(self):
        self.assertEqual(benchmark.decode_datagram(self.frame(), socket.PACKET_OUTGOING, 24683), (40000, 32, 4))
        self.assertEqual(benchmark.decode_datagram(self.frame(options=4), socket.PACKET_OUTGOING, 24683), (40000, 36, 4))

    def test_loopback_copy_and_client_input_are_excluded(self):
        self.assertIsNone(benchmark.decode_datagram(self.frame(), socket.PACKET_HOST, 24683))
        self.assertIsNone(benchmark.decode_datagram(self.frame(source=40000), socket.PACKET_OUTGOING, 24683))
        self.assertIsNone(benchmark.decode_datagram(b"short", socket.PACKET_OUTGOING, 24683))

    def test_nearest_rank_and_empty_samples(self):
        self.assertEqual(benchmark.distribution([]), {})
        self.assertEqual(benchmark.distribution(list(range(1, 101)))["p95"], 95)


if __name__ == "__main__":
    unittest.main()
