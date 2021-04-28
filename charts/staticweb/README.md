# StaticWeb

A chart to serve a static website

Include static files with your helm values or point at a git repo.

Key settings:
- giturl
- gitbranch  (default = "" meaning default-branch)
- pollInterval  (default 5 mins)
- rootFolder (path to the folder you want to serve, if not the repo root)

If you leave `giturl` blank, it'll serve any docs included in `files:` and `binaryFiles:`

Example:
```yaml
files:
  index.html: |
    <!DOCTYPE html!>
    <html>
      <body>
        <h1>Hello World</h1>
        <a href="/page2.html">page 2</a>
      </body>
    </html>

  page2.html: |
    <!DOCTYPE html!>
    <html>
      <body>
        <h1>Page 2</h1>
        <a href="/index.html">home</a>
      </body>
    </html>
```

To trust a private certificate authority, add the certificate to `cacert:`

Example:
```yaml
  cacert: |-
    -----BEGIN CERTIFICATE-----
    MIIGZDCCBMygAwIBAgIJAJVKt2jh/CCaMA0GCSqGSIb3DQEBDQUAMIHKMQswCQYD
    VQQGEwJVUzEVMBMGA1UECBMMUGVubnN5bHZhbmlhMRMwEQYDVQQHEwpQaXR0c2J1
    …
    eCdf0fDwd3GQOjQl46HVhLaj8WkKOKAsRw3qXz4vxcje9T6Vr0eVmRoW3W7zCRFO
    C13gD46YCVk=
    -----END CERTIFICATE-----

```
