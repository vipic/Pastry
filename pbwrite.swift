import AppKit

let args = CommandLine.arguments.dropFirst()

if args.isEmpty {
    print("usage: pbwrite file <path> ...")
    print("       pbwrite url <url>")
    print("       pbwrite html <string>")
    print("       pbwrite rtf <path-to-rtf-file>")
    print("       pbwrite image <path-to-png>")
    exit(0)
}

let mode = args.first!
let pb = NSPasteboard.general

switch mode {
case "file":
    let paths = args.dropFirst().map { String($0) }
    guard !paths.isEmpty else { print("err: no paths"); exit(1) }

    // NSFilenamesPboardType：与 Finder 多文件复制一致，写数组一次到位
    let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    pb.clearContents()
    pb.setPropertyList(paths, forType: filenamesType)
    pb.setString(paths.joined(separator: "\n"), forType: .string)

case "url":
    guard let urlStr = args.dropFirst().first else { print("err: no url"); exit(1) }
    let item = NSPasteboardItem()
    item.setString(urlStr, forType: .string)
    if let url = URL(string: urlStr) {
        item.setString(url.absoluteString, forType: .URL)
    }
    pb.clearContents()
    pb.writeObjects([item])

case "html":
    guard var html = args.dropFirst().first else { print("err: no html"); exit(1) }
    if !html.lowercased().contains("<html") {
        html = "<!DOCTYPE html><html><head><meta charset=\"UTF-8\"></head><body>\(html)</body></html>"
    }
    guard let data = html.data(using: .utf8) else { print("err: utf8 encode"); exit(1) }
    pb.clearContents()
    pb.setString(html, forType: .string)
    pb.setData(data, forType: .html)

case "image":
    guard let imgPath = args.dropFirst().first else { print("err: no path"); exit(1) }
    guard let image = NSImage(contentsOfFile: imgPath) else {
        print("err: cannot load image at \(imgPath)"); exit(1)
    }
    pb.clearContents()
    pb.writeObjects([image])

case "rtf":
    guard let rtfPath = args.dropFirst().first else { print("err: no path"); exit(1) }
    guard let rtfData = try? Data(contentsOf: URL(fileURLWithPath: rtfPath)),
          let _ = String(data: rtfData, encoding: .utf8) else {
        print("err: cannot read rtf at \(rtfPath)"); exit(1)
    }
    pb.clearContents()
    pb.setString(String(data: rtfData, encoding: .utf8)!, forType: .string)
    pb.setData(rtfData, forType: .rtf)

default:
    print("err: unknown mode \(mode)")
    exit(1)
}

print("ok")
