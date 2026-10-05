function FindProxyForURL(url, host) {

    // Bypass localhost
    if (
        isPlainHostName(host) ||
        shExpMatch(host, "localhost") ||
        shExpMatch(host, "127.*")
    ) {
        return "DIRECT";
    }


    // Internal domain
    if (dnsDomainIs(host, ".example.com")) {
        return "DIRECT";
    }


    // Internal IP ranges
    if (
        isInNet(host, "10.0.0.0", "255.0.0.0") ||
        isInNet(host, "172.16.0.0", "255.240.0.0") ||
        isInNet(host, "192.168.0.0", "255.255.0.0")
    ) {
        return "DIRECT";
    }


    // Everything else through Squid
    return "PROXY proxy.example.com:3128; DIRECT";
}