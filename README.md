# che-custom-nodejs-deasync
Provides a custom nodejs binary embedding deasync node-gyp module as builtin module

# Build multi-arch image from separate tags:
```bash
docker manifest create quay.io/eclipse/che-custom-nodejs-deasync:10.20.1 \
       quay.io/eclipse/che-custom-nodejs-deasync:10.20.1-linux-arm64 \
       quay.io/eclipse/che-custom-nodejs-deasync:10.20.1-linux-ppc64le \
       quay.io/eclipse/che-custom-nodejs-deasync:10.20.1-linux-s390x \
       quay.io/eclipse/che-custom-nodejs-deasync:10.20.1-linux-amd64
```

review it
```bash
$ docker manifest inspect quay.io/eclipse/che-custom-nodejs-deasync:10.20.1
```

push:
```bash
$ docker manifest push quay.io/eclipse/che-custom-nodejs-deasync:10.20.1
```
