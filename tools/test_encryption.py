"""The locked fixture's encryption: RC4 against the specification's vectors, and determinism."""
import unittest

from pdfreflow_tools.encryption import PAD, encrypted_pdf, file_key, object_key, owner_entry, rc4


class RC4Tests(unittest.TestCase):
    def test_known_answers(self):
        # Test vectors from RFC 6229 section 2, the first 16 keystream bytes of each key.
        for key, expected in ((b'\x01\x02\x03\x04\x05', '\xb2\x39\x63\x05\xf0\x3d\xc0\x27'
                                                        '\xcc\xc3\x52\x4a\x0a\x11\x18\xa8'),
                              (b'\x01\x02\x03\x04\x05\x06\x07', '\x29\x3f\x02\xd4\x7f\x37\xc9\xb6'
                                                                '\x33\xf2\xaf\x52\x85\xfe\xb4\x6b')):
            self.assertEqual(rc4(key, bytes(16)), expected.encode('latin-1'))

    def test_is_its_own_inverse(self):
        self.assertEqual(rc4(b'key', rc4(b'key', b'a locked page')), b'a locked page')


class StandardSecurityHandlerTests(unittest.TestCase):
    def test_entries_have_the_lengths_the_handler_defines(self):
        owner = owner_entry('reflow-owner', 'reflow')
        self.assertEqual(len(owner), 32)
        self.assertEqual(len(file_key('reflow', owner)), 5)
        self.assertEqual(len(object_key(file_key('reflow', owner), 4)), 10)

    def test_the_padding_string_is_the_one_the_specification_states(self):
        self.assertEqual(len(PAD), 32)
        self.assertEqual(PAD[:4], bytes([0x28, 0xBF, 0x4E, 0x5E]))

    def test_a_different_password_derives_a_different_key(self):
        owner = owner_entry('reflow-owner', 'reflow')
        self.assertNotEqual(file_key('reflow', owner), file_key('reflow ', owner))


class FixtureTests(unittest.TestCase):
    def test_the_fixture_is_the_same_bytes_every_time(self):
        self.assertEqual(encrypted_pdf(), encrypted_pdf())

    def test_the_fixture_is_an_encrypted_pdf_whose_text_is_not_in_the_clear(self):
        data = encrypted_pdf()
        self.assertTrue(data.startswith(b'%PDF-1.4\n'))
        self.assertIn(b'/Filter /Standard /V 1 /R 2', data)
        self.assertIn(b'/Encrypt 6 0 R', data)
        self.assertNotIn(b'A locked page', data)

    def test_the_cross_reference_offsets_address_their_objects(self):
        data = encrypted_pdf()
        start = int(data.rsplit(b'startxref\n', 1)[1].split(b'\n', 1)[0])
        rows = data[start:].split(b'\n')[2:]
        for number, row in enumerate(rows, start=1):
            if not row.endswith(b'n '):
                break
            self.assertTrue(data[int(row.split()[0]):].startswith(b'%d 0 obj' % number))


if __name__ == '__main__':
    unittest.main()
