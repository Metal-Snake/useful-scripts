# Filename: pushnotify.py
# Laden: /msg *status loadmod pushnotify
#
# Befehle:
#   /msg *pushnotify add <wort>
#   /msg *pushnotify del <wort>
#   /msg *pushnotify list
#   /msg *pushnotify topic <topic>
#   /msg *pushnotify server <url>
#   /msg *pushnotify test <nachricht>

import znc
import subprocess
import re

class pushnotify(znc.Module):
    description = "Sendet eine Pushmeldung via ntfy bei Schlüsselwörtern oder Regex"

    def OnLoad(self, args, message):
        if "keywords" not in self.nv:
            self.nv["keywords"] = ""
        if "raw_keywords" not in self.nv:
            self.nv["raw_keywords"] = ""
        if "ntfy_topic" not in self.nv:
            self.nv["ntfy_topic"] = "dein-topic"
        if "ntfy_server" not in self.nv:
            self.nv["ntfy_server"] = "https://ntfy.sh"
        return True

    def OnPrivMsg(self, nick, message):
        self.check_message(nick.GetNick(), "Privat", message.s)
        return znc.CONTINUE

    def OnChanMsg(self, nick, channel, message):
        self.check_message(nick.GetNick(), channel.GetName(), message.s)
        return znc.CONTINUE

    def check_message(self, sender, context, text):
        for kw in self.get_keywords():
            try:
                if re.search(kw, text, re.IGNORECASE):
                    self.send_push(sender, context, text)
                    break
            except re.error as e:
                self.PutModule(f"Ungültiger Regex '{kw}': {e}")

    def send_push(self, sender, context, text):
        push_text = f"[{context}] <{sender}> {text}"
        self.do_push(push_text)

    def do_push(self, push_text):
        topic = self.nv.get("ntfy_topic", "dein-topic")
        server = self.nv.get("ntfy_server", "https://ntfy.sh")
        url = f"{server.rstrip('/')}/{topic}"
        subprocess.run([
            "curl", "-s",
            "-d", push_text,
            url
        ])

    # ---- Keyword-Verwaltung ----
    def get_keywords(self):
        return [kw.strip() for kw in self.nv.get("keywords", "").split(",") if kw.strip()]

    def get_raw_keywords(self):
        return [kw.strip() for kw in self.nv.get("raw_keywords", "").split(",") if kw.strip()]

    def save_keywords(self, raw_list, regex_list):
        self.nv["raw_keywords"] = ",".join(raw_list)
        self.nv["keywords"] = ",".join(regex_list)

    def normalize_keyword(self, kw):
        """Wenn kein Regex explizit angegeben wurde (/regex/), 
        wird automatisch ein Wort-Grenzen-Regex erzeugt."""
        if kw.startswith("/") and kw.endswith("/") and len(kw) > 2:
            return kw[1:-1]  # echten Regex übernehmen
        else:
            return rf"\b{re.escape(kw)}\b"  # exaktes Wort matchen

    # ---- User-Befehle ----
    def OnModCommand(self, command):
        parts = command.strip().split(" ", 1)
        cmd = parts[0].lower()

        if cmd == "add" and len(parts) > 1:
            raw_kw = parts[1].strip()
            regex_kw = self.normalize_keyword(raw_kw)

            raw_list = self.get_raw_keywords()
            regex_list = self.get_keywords()

            if regex_kw not in regex_list:
                try:
                    re.compile(regex_kw)
                    raw_list.append(raw_kw)
                    regex_list.append(regex_kw)
                    self.save_keywords(raw_list, regex_list)
                    self.PutModule(f"'{raw_kw}' hinzugefügt (Regex: {regex_kw}).")
                except re.error as e:
                    self.PutModule(f"Ungültiger Regex: {e}")
            else:
                self.PutModule(f"'{raw_kw}' existiert bereits.")

        elif cmd == "del" and len(parts) > 1:
            raw_kw = parts[1].strip()
            regex_kw = self.normalize_keyword(raw_kw)

            raw_list = self.get_raw_keywords()
            regex_list = self.get_keywords()

            if regex_kw in regex_list:
                idx = regex_list.index(regex_kw)
                del regex_list[idx]
                del raw_list[idx]
                self.save_keywords(raw_list, regex_list)
                self.PutModule(f"'{raw_kw}' entfernt.")
            else:
                self.PutModule(f"'{raw_kw}' nicht gefunden.")

        elif cmd == "list":
            raw_list = self.get_raw_keywords()
            regex_list = self.get_keywords()
            topic = self.nv.get("ntfy_topic", "dein-topic")
            server = self.nv.get("ntfy_server", "https://ntfy.sh")

            if raw_list:
                self.PutModule("Aktuelle Keywords/Regex:")
                for raw, regex in zip(raw_list, regex_list):
                    self.PutModule(f"  Eingabe: {raw}   →   Regex: {regex}")
            else:
                self.PutModule("Keine Keywords gesetzt.")

            self.PutModule(f"Aktueller ntfy-Topic: {topic}")
            self.PutModule(f"Aktueller ntfy-Server: {server}")

        elif cmd == "topic" and len(parts) > 1:
            topic = parts[1].strip()
            self.nv["ntfy_topic"] = topic
            self.PutModule(f"ntfy-Topic auf '{topic}' gesetzt.")

        elif cmd == "server" and len(parts) > 1:
            server = parts[1].strip()
            self.nv["ntfy_server"] = server
            self.PutModule(f"ntfy-Server auf '{server}' gesetzt.")

        elif cmd == "test" and len(parts) > 1:
            msg = parts[1].strip()
            self.do_push(f"[TEST] {msg}")
            self.PutModule("Testnachricht gesendet.")

        else:
            self.PutModule("Befehle: add <wort|/regex/>, del <wort|/regex/>, list, topic <topic>, server <url>, test <msg>")
