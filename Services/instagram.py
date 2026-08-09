#!/usr/bin/env python3
"""Daemon de DMs de Instagram para la vista del sidebar.

Lo lanza Services/InstagramService.qml con un único argumento JSON:

    {"session": "<ruta del session.json>", "thread": "<username>", "amount": 30}

y le habla por stdin, una orden JSON por línea:

    {"cmd": "threads"}                      -> {"type":"threads","items":[...]}
    {"cmd": "open", "id": "<id|username>"}  -> {"type":"opened","id":...,"title":...}
    {"cmd": "fetch"}                        -> {"type":"messages","items":[...]}
    {"cmd": "send", "text": "", "replyTo": "<id>|null"} -> {"type":"sent"}

Al arrancar emite {"type":"ready"} o {"type":"error","text":...}, y si el
config traía un hilo recordado lo abre ahí mismo.

Cada mensaje es {"mid","role","text","reply"} con role "me" | "them" y reply
vacío salvo que ese mensaje sea una respuesta citada. Cada hilo del selector es
{"tid","title","preview","unread"}. Las claves son mid/tid y no "id" porque
esos objetos van directo a un ListModel y en QML `id` es palabra reservada.

Es un daemon y no un proceso por consulta porque importar instagrapi y
levantar la sesión cuesta un par de segundos: con polling eso se pagaría en
cada refresco. Acá se paga una vez y el cliente queda en memoria.

Instagram no tiene API de DMs para cuentas personales, así que esto usa
instagrapi (API privada del cliente móvil). El login va aparte y a mano:

    python3 instagram.py --login <ruta del session.json>

Sin instagrapi instalado, sin sesión válida o sin hilo configurado el daemon
NO se muere: contesta {"type":"error"} a cada orden y sigue leyendo stdin. Un
proceso que desaparece deja el panel mudo y sin explicación.
"""

import json
import os
import sys


def emit(**obj):
    # flush obligatorio: stdout a un pipe se buferea por bloques y QML no
    # vería una línea hasta llenar 4K, o sea nunca.
    print(json.dumps(obj), flush=True)


def fail(text):
    emit(type="error", text=text)


class Session:
    """Cliente + hilo resuelto. `error` no vacío significa inutilizable."""

    def __init__(self, cfg):
        self.cfg = cfg
        self.client = None
        self.thread_id = None
        self.title = ""
        self.error = ""
        self.cache = {}         # id -> DirectMessage, para citar (ver send)
        try:
            self._connect()
        except Exception as e:
            self.error = "%s: %s" % (type(e).__name__, e)

    def _connect(self):
        from instagrapi import Client

        path = self.cfg["session"]
        if not os.path.exists(path):
            raise RuntimeError("no hay sesión en %s (corré --login)" % path)

        self.client = Client()
        self.client.load_settings(path)
        # load_settings solo restaura cookies; nada garantiza que sigan
        # vivas. Una llamada barata falla acá y no a mitad de un send.
        self.client.get_timeline_feed()

    @staticmethod
    def _title(thread):
        return thread.thread_title or ", ".join(u.username for u in thread.users)

    def threads(self):
        items = []
        for t in self.client.direct_threads(amount=20):
            last = t.messages[0] if t.messages else None
            items.append({
                # tid/mid y no "id": en QML `id` es palabra reservada y no se
                # puede declarar como propiedad de un delegate.
                "tid": str(t.id),
                "title": self._title(t),
                "preview": (last.text or "[media]") if last else "",
                "unread": bool(t.read_state),
            })
        emit(type="threads", items=items)

    def open(self, ref):
        """Abre un hilo por id o por username.

        El selector manda ids, pero un `thread` escrito a mano en config.json
        sigue siendo un username: se distinguen porque el id es solo dígitos.
        """
        ref = str(ref).lstrip("@")
        if ref.isdigit():
            def matches(t):
                return str(t.id) == ref
        else:
            def matches(t):
                return any(u.username == ref for u in t.users)

        for thread in self.client.direct_threads(amount=50):
            if matches(thread):
                self.thread_id = str(thread.id)
                self.title = self._title(thread)
                self.cache = {}
                emit(type="opened", id=self.thread_id, title=self.title)
                return
        raise RuntimeError("no encontré la conversación %s" % ref)

    def fetch(self):
        if not self.thread_id:
            raise RuntimeError("no hay conversación abierta")
        msgs = self.client.direct_messages(self.thread_id,
                                           amount=self.cfg["amount"])
        # Los objetos completos, no solo los ids: direct_send necesita el
        # client_context del mensaje original para enganchar la cita.
        self.cache = {str(m.id): m for m in msgs}
        items = []
        for m in reversed(msgs):          # la API los da del más nuevo al más viejo
            items.append({
                "mid": str(m.id),
                "role": "me" if m.is_sent_by_viewer else "them",
                # Un DM sin texto es una foto, un reel o una story compartida.
                # No se renderizan, pero omitirlos deja huecos raros en el hilo.
                "text": m.text if m.text else "[media]",
                "reply": (m.reply.text or "[media]") if m.reply else "",
            })
        emit(type="messages", items=items)

    def send(self, text, reply_to=None):
        if not self.thread_id:
            raise RuntimeError("no hay conversación abierta")
        original = None
        if reply_to:
            original = self.cache.get(str(reply_to))
            if original is None:
                # Mandarlo suelto sin avisar sería peor: el usuario creería que
                # citó y del otro lado llegaría un mensaje sin contexto.
                raise RuntimeError("ese mensaje ya no está en la ventana cargada")
        self.client.direct_send(text, thread_ids=[self.thread_id],
                                reply_to_message=original)
        emit(type="sent")


def login(path):
    """Login interactivo. Es lo único que ve la contraseña; el sidebar no."""
    import getpass
    from instagrapi import Client

    client = Client()
    user = input("usuario de Instagram: ").strip()
    password = getpass.getpass("contraseña: ")
    code = input("código 2FA (Enter si no tenés): ").strip()

    client.login(user, password, verification_code=code)
    client.dump_settings(path)
    os.chmod(path, 0o600)
    print("sesión guardada en %s" % path)


def selfcheck():
    """Chequea con dobles lo que no se puede probar sin sesión: que open()
    distinga id de username y que send() no mande una cita rota.

    Correr con: instagram.py --selfcheck
    """
    class FakeUser:
        def __init__(self, username):
            self.username = username

    class FakeThread:
        def __init__(self, tid, username):
            self.id = tid
            self.thread_title = ""
            self.users = [FakeUser(username)]
            self.messages = []

    class FakeClient:
        sent = None

        def direct_threads(self, amount=20):
            return [FakeThread("111", "ana"), FakeThread("222", "beto")]

        def direct_send(self, text, thread_ids=None, reply_to_message=None):
            FakeClient.sent = (text, reply_to_message)

    s = Session.__new__(Session)          # sin __init__: no queremos conectar
    s.cfg = {"amount": 30}
    s.client = FakeClient()
    s.thread_id = None
    s.title = ""
    s.cache = {}

    s.open("222")                          # todo dígitos -> id
    assert s.thread_id == "222", s.thread_id
    s.open("ana")                          # con letras -> username
    assert s.thread_id == "111", s.thread_id
    assert s.title == "ana", s.title
    try:
        s.open("nadie")
        raise AssertionError("un hilo inexistente debería explotar")
    except RuntimeError:
        pass

    # Citar un mensaje fuera de la ventana cargada tiene que fallar, no
    # degradar a mensaje suelto sin que el usuario se entere.
    try:
        s.send("hola", reply_to="9999")
        raise AssertionError("citar algo ausente del caché debería explotar")
    except RuntimeError:
        pass
    assert FakeClient.sent is None

    sentinel = object()
    s.cache = {"42": sentinel}
    s.send("hola", reply_to="42")
    assert FakeClient.sent == ("hola", sentinel), FakeClient.sent
    s.send("suelto")
    assert FakeClient.sent == ("suelto", None), FakeClient.sent

    print("selfcheck OK")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--selfcheck":
        selfcheck()
        return 0

    if len(sys.argv) > 1 and sys.argv[1] == "--login":
        if len(sys.argv) < 3:
            sys.stderr.write("uso: instagram.py --login <ruta del session.json>\n")
            return 2
        login(sys.argv[2])
        return 0

    cfg = json.loads(sys.argv[1])
    cfg.setdefault("amount", 30)

    session = Session(cfg)
    if session.error:
        fail(session.error)
    else:
        emit(type="ready")
        # Reabrir la última selección: sin esto la vista caería en el selector
        # en cada arranque del shell. Que falle (el hilo se archivó, cambió de
        # id) no invalida la sesión: se avisa y queda el selector.
        if cfg.get("thread"):
            try:
                session.open(cfg["thread"])
            except Exception as e:
                fail("%s: %s" % (type(e).__name__, e))

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            order = json.loads(line)
        except ValueError:
            fail("orden ilegible")
            continue

        if session.error:
            fail(session.error)
            continue

        try:
            cmd = order.get("cmd")
            if cmd == "fetch":
                session.fetch()
            elif cmd == "send":
                session.send(order.get("text", ""), order.get("replyTo"))
            elif cmd == "threads":
                session.threads()
            elif cmd == "open":
                session.open(order.get("id", ""))
            else:
                fail("orden desconocida: %s" % cmd)
        except Exception as e:
            # Un fallo puntual (red caída, rate limit) no invalida la sesión:
            # se reporta y el próximo poll reintenta.
            fail("%s: %s" % (type(e).__name__, e))
    return 0


if __name__ == "__main__":
    sys.exit(main())
