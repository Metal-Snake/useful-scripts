# pushnotify.py
# Drop in ~/.znc/modules/ and reload the module:
# /msg *status unloadmod pushnotify
# /msg *status loadmod pushnotify
#
# Befehle:
#   /msg *pushnotify add [-s|-i] <wort|/regex/>
#   /msg *pushnotify del <idx|wort|/regex/>
#   /msg *pushnotify clear
#   /msg *pushnotify list
#   /msg *pushnotify topic <topic>
#   /msg *pushnotify server <url>
#   /msg *pushnotify test <nachricht>
#   /msg *pushnotify click <url>|off   (Igloo Click-Feature)
#   /msg *pushnotify action on|off    (Igloo Action-Button)

import znc
import subprocess
import re
import json
import traceback

class pushnotify(znc.Module):
    description = "Sendet Pushmeldungen via ntfy bei Schlüsselwörtern oder Regex"
    module_types = [znc.CModInfo.UserModule]

    def OnLoad(self, args, message):
        # Robustes JSON-basiertes Speichern
        if "keywords_json" not in self.nv:
            self.nv["keywords_json"] = "[]"
        if "ntfy_topic" not in self.nv:
            self.nv["ntfy_topic"] = "dein-topic"
        if "ntfy_server" not in self.nv:
            self.nv["ntfy_server"] = "https://ntfy.sh"
        if "igloo_click_url" not in self.nv:
            self.nv["igloo_click_url"] = ""
        if "igloo_action_button" not in self.nv:
            self.nv["igloo_action_button"] = "false"
        return True

    # ---- Utilities für Speicherung ----
    def _get_items(self):
        """Gibt Liste von Dicts zurück: {raw, regex, flag}"""
        s = self.nv.get("keywords_json", "[]")
        try:
            items = json.loads(s)
            if isinstance(items, list):
                return items
        except Exception:
            pass
        # falls korrupt: zurücksetzen, aber die alte Rohdaten nicht heimlich verlieren
        return []

    def _save_items(self, items):
        self.nv["keywords_json"] = json.dumps(items)

    def _normalize(self, raw):
        """Wenn raw mit /.../ angegeben wird, ist es echter Regex (ohne Slashes).
           Sonst: exaktes Wort => \bescaped\b"""
        if raw.startswith("/") and raw.endswith("/") and len(raw) > 2:
            return raw[1:-1]
        return r"\b%s\b" % re.escape(raw)

    # ---- Push/Send ----
    def send_push(self, sender, context, text):
        push_text = f"[{context}] <{sender}> {text}"
        self._do_push(push_text)

    def _do_push(self, push_text, title=None):
        topic = self.nv.get("ntfy_topic", "dein-topic")
        server = self.nv.get("ntfy_server", "https://ntfy.sh")
        url = f"{server.rstrip('/')}/{topic}"

        click_url = self.nv.get("igloo_click_url", "")
        action_enabled = self.nv.get("igloo_action_button", "false").lower() == "true"

        cmd = ["curl", "-s", "-d", push_text]

        if title:
            cmd.extend(["-H", f"Title: {title}"])

        if click_url:
            cmd.extend(["-H", f"Click: {click_url}"])

        if action_enabled:
            actions = json.dumps([{
                "action": "view",
                "label": "Open Igloo",
                "url": "igloo://",
                "clear": False
            }])
            cmd.extend(["-H", f"Actions: {actions}"])

        cmd.append(url)

        try:
            subprocess.run(cmd, check=False)
        except Exception as e:
            self.PutModule(f"Fehler beim Senden: {e}")

    # ---- Hooks ----
    def OnPrivMsg(self, nick, message):
        self._check_message(nick.GetNick(), "Privat", message.s)
        return znc.CONTINUE

    def OnChanMsg(self, nick, channel, message):
        self._check_message(nick.GetNick(), channel.GetName(), message.s)
        return znc.CONTINUE

    def _check_message(self, sender, context, text):
        for it in self._get_items():
            regex = it.get("regex", "")
            flag = it.get("flag", "ignorecase")
            try:
                fl = re.IGNORECASE if flag == "ignorecase" else 0
                if re.search(regex, text, fl):
                    self.send_push(sender, context, text)
                    break
            except re.error as e:
                # Fehler in einem gespeicherten Regex sichtbar machen
                self.PutModule(f"Ungültiger gespeicherter Regex '{regex}': {e}")

    # ---- Command-Handling (robust, mit Debug-Ausgabe) ----
    def OnModCommand(self, command):
        # debug: immer sichtbar machen, dass OnModCommand angekommen ist
        if command is None:
            command = ""
        cmdline = command.strip()

        try:
            if not cmdline:
                self.PutModule("Befehle: add [-s|-i] <wort|/regex/>, del <idx|wort|/regex/>, clear, list, topic <topic>, server <url>, test <msg>, click <url>|off, action on|off, id")
                return

            parts = cmdline.split(" ", 2)
            cmd = parts[0].lower()

            # ---- add ----
            if cmd == "add":
                # support: add [-s|-i] <wort|/regex/>
                flag = "ignorecase"
                if len(parts) >= 2 and parts[1] in ("-s", "-i"):
                    flag = "sensitive" if parts[1] == "-s" else "ignorecase"
                    if len(parts) < 3:
                        self.PutModule("Usage: add [-s|-i] <wort|/regex/>")
                        return
                    raw = parts[2].strip()
                elif len(parts) >= 2:
                    raw = " ".join(parts[1:]).strip()
                else:
                    self.PutModule("Usage: add [-s|-i] <wort|/regex/>")
                    return

                regex = self._normalize(raw)
                # prüfen, ob regex kompiliert
                try:
                    re.compile(regex)
                except re.error as e:
                    self.PutModule(f"Ungültiger Regex: {e}")
                    return

                items = self._get_items()
                # Duplikatprüfung: gleiche raw+flag oder gleiche regex+flag
                for it in items:
                    if it.get("raw") == raw and it.get("flag") == flag:
                        self.PutModule(f"'{raw}' mit Flag {flag} existiert bereits.")
                        return
                    if it.get("regex") == regex and it.get("flag") == flag:
                        self.PutModule(f"Regex '{regex}' mit Flag {flag} existiert bereits.")
                        return

                items.append({"raw": raw, "regex": regex, "flag": flag})
                self._save_items(items)
                self.PutModule(f"'{raw}' hinzugefügt (Regex: {regex}, Flag: {flag}).")
                return

            # ---- del ----
            if cmd == "del":
                if len(parts) < 2:
                    self.PutModule("Usage: del <idx|wort|/regex/>")
                    return
                arg = parts[1].strip()
                items = self._get_items()
                removed = None

                # per index löschen
                if arg.isdigit():
                    idx = int(arg) - 1
                    if 0 <= idx < len(items):
                        removed = items.pop(idx)
                else:
                    # match per raw (case-insensitive) oder per regex exakt oder per raw exact
                    new = []
                    for it in items:
                        if removed is None and (it.get("raw","").lower() == arg.lower() or it.get("regex","") == arg or it.get("raw","") == arg):
                            removed = it
                            continue
                        new.append(it)
                    items = new

                if removed:
                    self._save_items(items)
                    self.PutModule(f"Entfernt: {removed.get('raw')} -> {removed.get('regex')}")
                else:
                    self.PutModule(f"'{arg}' nicht gefunden.")
                return

            # ---- clear ----
            if cmd == "clear":
                self._save_items([])
                self.PutModule("Alle Keywords gelöscht.")
                return

            # ---- list ----
            if cmd == "list":
                items = self._get_items()
                topic = self.nv.get("ntfy_topic", "dein-topic")
                server = self.nv.get("ntfy_server", "https://ntfy.sh")
                click_url = self.nv.get("igloo_click_url", "")
                action_enabled = self.nv.get("igloo_action_button", "false") == "true"

                self.PutModule("Aktuelle Keywords/Regex:")
                if items:
                    for idx, it in enumerate(items, 1):
                        raw = it.get("raw", "")
                        regex = it.get("regex", "")
                        flag = it.get("flag", "ignorecase")
                        mode = "[ignorecase]" if flag == "ignorecase" else "[case-sensitive]"
                        self.PutModule(f"  {idx}. Eingabe: {raw}   →   Regex: {regex}   {mode}")
                else:
                    self.PutModule("  (keine gesetzt)")

                self.PutModule(f"Aktueller ntfy-Topic: {topic}")
                self.PutModule(f"Aktueller ntfy-Server: {server}")

                if click_url:
                    self.PutModule(f"Igloo Click-URL: {click_url}")
                else:
                    self.PutModule("Igloo Click-URL: (deaktiviert)")

                self.PutModule(f"Igloo Action-Button: {'an' if action_enabled else 'aus'}")
                return

            # ---- topic ----
            if cmd == "topic" and len(parts) > 1:
                topic = parts[1].strip()
                self.nv["ntfy_topic"] = topic
                self.PutModule(f"ntfy-Topic auf '{topic}' gesetzt.")
                return

            # ---- server ----
            if cmd == "server" and len(parts) > 1:
                server = parts[1].strip()
                self.nv["ntfy_server"] = server
                self.PutModule(f"ntfy-Server auf '{server}' gesetzt.")
                return

            # ---- test ----
            if cmd == "test" and len(parts) > 1:
                msg = parts[1].strip()
                self._do_push(f"[TEST] {msg}")
                self.PutModule("Testnachricht gesendet.")
                return

            # ---- click (Igloo Click-URL) ----
            if cmd == "click":
                if len(parts) > 1:
                    url = parts[1].strip()
                    if url.lower() == "off":
                        self.nv["igloo_click_url"] = ""
                        self.PutModule("Click-Feature deaktiviert.")
                    else:
                        self.nv["igloo_click_url"] = url
                        self.PutModule(f"Click-URL auf '{url}' gesetzt.")
                else:
                    current = self.nv.get("igloo_click_url", "")
                    if current:
                        self.PutModule(f"Aktuelle Click-URL: {current}")
                    else:
                        self.PutModule("Click-Feature ist deaktiviert (keine URL gesetzt).")
                return

            # ---- action (Igloo Action-Button) ----
            if cmd == "action":
                if len(parts) > 1:
                    val = parts[1].strip().lower()
                    if val in ("on", "true", "1"):
                        self.nv["igloo_action_button"] = "true"
                        self.PutModule("Action-Button aktiviert.")
                    elif val in ("off", "false", "0"):
                        self.nv["igloo_action_button"] = "false"
                        self.PutModule("Action-Button deaktiviert.")
                    else:
                        self.PutModule("Usage: action on|off")
                else:
                    enabled = self.nv.get("igloo_action_button", "false") == "true"
                    self.PutModule(f"Action-Button: {'an' if enabled else 'aus'}")
                return

            # ---- id (debug) ----
            if cmd == "id":
                net = self.GetNetwork().GetName() if self.GetNetwork() else "-"
                try:
                    path = __file__
                except Exception:
                    path = "(unbekannt)"
                self.PutModule(f"Instance: network='{net}', file='{path}'")
                return

            # unbekannt
            self.PutModule(f"Unbekanntes Kommando: {cmd}")
            return

        except Exception as e:
            # Wichtig: wir fangen jede Exception und geben den Trace in den IRC-Channel,
            # damit nicht die kryptische ZNC-Fehlermeldung kommt.
            self.PutModule("Fehler in OnModCommand: " + str(e))
            for line in traceback.format_exc().splitlines():
                # PutModule hat Beschränkungen pro Zeile, aber das ist besser als nichts.
                self.PutModule(line)
            return