"""Summarize a pcap (Ethernet/IPv4): DNS queries/answers, TCP flags, TLS record
types -- enough to see where the guest's HTTPS to the registry stops."""
import struct, sys
f = open(sys.argv[1], "rb").read()
off = 24
i = 0
t0 = None
while off + 16 <= len(f) and i < 60:
    ts, tus, caplen, length = struct.unpack("<IIII", f[off:off + 16])
    fr = f[off + 16:off + 16 + caplen]
    off += 16 + caplen
    t = ts + tus / 1e6
    t0 = t0 or t
    et = fr[12:14].hex()
    line = f"{i:3d} +{t - t0:6.2f}s "
    if et == "0806":
        line += "arp"
    elif et == "0800" and len(fr) >= 34:
        ihl = (fr[14] & 15) * 4
        proto = fr[23]
        src = ".".join(map(str, fr[26:30]))
        dst = ".".join(map(str, fr[30:34]))
        l4 = fr[14 + ihl:]
        if proto == 17 and len(l4) >= 8:
            sp, dp = struct.unpack(">HH", l4[:4])
            pl = l4[8:]
            line += f"udp {src}:{sp} -> {dst}:{dp}"
            if 53 in (sp, dp) and len(pl) >= 12:
                qd, an = struct.unpack(">HH", pl[4:8])
                flags = struct.unpack(">H", pl[2:4])[0]
                p = 12
                name = []
                while p < len(pl) and pl[p]:
                    n = pl[p]
                    name.append(pl[p + 1:p + 1 + n].decode("ascii", "replace"))
                    p += 1 + n
                line += f" DNS {'resp' if flags & 0x8000 else 'query'} {'.'.join(name)} rcode={flags & 15} answers={an}"
        elif proto == 6 and len(l4) >= 20:
            sp, dp = struct.unpack(">HH", l4[:4])
            doff = (l4[12] >> 4) * 4
            fl = l4[13]
            names = [n for b, n in ((2, "SYN"), (16, "ACK"), (1, "FIN"), (4, "RST"), (8, "PSH")) if fl & b]
            pl = l4[doff:]
            line += f"tcp {src}:{sp} -> {dst}:{dp} {'|'.join(names)} len={len(pl)}"
            if pl and pl[0] in (20, 21, 22, 23):
                kind = {20: "ccs", 21: "ALERT", 22: "handshake", 23: "appdata"}[pl[0]]
                line += f" tls:{kind}"
                if pl[0] == 22 and len(pl) > 5:
                    line += f"/{ {1: 'ClientHello', 2: 'ServerHello', 11: 'Certificate', 12: 'ServerKeyExchange', 14: 'ServerHelloDone', 16: 'ClientKeyExchange', 20: 'Finished'}.get(pl[5], pl[5]) }"
                if pl[0] == 21 and len(pl) >= 7:
                    line += f" level={pl[5]} desc={pl[6]}"
        else:
            line += f"ip proto={proto} {src} -> {dst}"
    else:
        line += f"ethertype {et}"
    print(line)
    i += 1
