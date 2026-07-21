import errno
import importlib.util
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).parents[1] / "tools" / "afalg-socket-test.py"
SPEC = importlib.util.spec_from_file_location("afalg_socket_test", MODULE_PATH)
afalg_socket_test = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(afalg_socket_test)


class FakeSocket:
    def __init__(self):
        self.closed = False

    def close(self):
        self.closed = True


class AfAlgProbeTests(unittest.TestCase):
    def test_blocked_policy_is_success(self):
        def denied(*_args):
            raise PermissionError(errno.EPERM, "denied")

        message, code = afalg_socket_test.probe(denied)
        self.assertEqual(code, 0)
        self.assertTrue(message.startswith("BLOCKED:"))

    def test_unsupported_runtime_is_distinct(self):
        def unsupported(*_args):
            raise OSError(errno.EAFNOSUPPORT, "unsupported")

        message, code = afalg_socket_test.probe(unsupported)
        self.assertEqual(code, 2)
        self.assertTrue(message.startswith("UNSUPPORTED:"))

    def test_unexpected_failure_is_an_error(self):
        def failed(*_args):
            raise OSError(errno.EIO, "input/output error")

        message, code = afalg_socket_test.probe(failed)
        self.assertEqual(code, 3)
        self.assertTrue(message.startswith("ERROR:"))

    def test_permitted_socket_is_closed_and_actionable(self):
        fake_socket = FakeSocket()

        message, code = afalg_socket_test.probe(lambda *_args: fake_socket)

        self.assertEqual(code, 10)
        self.assertTrue(fake_socket.closed)
        self.assertTrue(message.startswith("PERMITTED:"))


if __name__ == "__main__":
    unittest.main()
