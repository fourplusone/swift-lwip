// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "lwip",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "lwip",
            targets: ["LwIP"]),
        .library(
            name: "clwip",
            targets: ["CLwIP"])
        

    ],
    targets: [
        .target(name: "LwIP", dependencies:["CLwIP"]),
        .target(name: "CLwIP",
                cSettings: [
                    .headerSearchPath("config"),
                    .headerSearchPath("include"),
                    ]
                ),
        .testTarget(name: "LwIPTests", dependencies: ["LwIP"])
    ]
)
