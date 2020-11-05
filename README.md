SimpleCamera
===========

[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat-square)](https://github.com/Carthage/Carthage)


## ToDo

- Write Super Cool README.
- Make Ultra Cool Sample App.


## What is this

iOS のカメラハンドリングについて勉強がてら簡単なアプリを書いていったら段々面白くなってしまってしまったやつ。

最終的に巨大な Singleton になってしまって全然 Simple じゃなくなってしまった。


## Poem

最近の iOS 界隈というか Swift 界隈、型に厳密でクールでお洒落なライブラリじゃないとダサいみたいな風潮あると思うんだけど、完全に個人で自分が使うためだけに書いたというか、知らん、これは俺が使うんだ！！！俺こそがユーザーだ！！！


## Carthage

https://github.com/Carthage/Carthage

Write your `Cartfile`

```
github "dnpp73/SimpleCamera"
```

and run

```sh
carthage bootstrap --no-use-binaries --platform iOS
```


## How to Use

### See `Interface.swift`

- [`CameraFinderViewInterface.swift`](/Sources/View/CameraFinderViewInterface.swift)
- [`SimpleCameraInterface.swift`](/Sources/SimpleCameraInterface.swift)


## License

[MIT](/LICENSE)
