import UIKit
import WebKit

/**
 Markdown View for iOS.
 
 - Note: [How to get height of entire document with javascript](https://stackoverflow.com/questions/1145850/how-to-get-height-of-entire-document-with-javascript)
 
 注意加载内容写法：
 let content = String.init(format: "<meta content=\"width=device-width, initial-scale=1.0, maximum-scale=3.0, user-scalable=0;\" name=\"viewport\" />%@<div id=\"testDiv\" style = \"height:10px; width:100px\"></div>", model.business_description)
 
 */
open class MarkdownView: UIView {

  private var webView: WKWebView?
  
  fileprivate var intrinsicContentHeight: CGFloat? {
    didSet {
      self.invalidateIntrinsicContentSize()
    }
  }

  public var isScrollEnabled: Bool = true {

    didSet {
      webView?.scrollView.isScrollEnabled = isScrollEnabled
    }

  }

  public var onTouchLink: ((URLRequest) -> Bool)?

  public var onRendered: ((CGFloat) -> Void)?

    
    @objc public var onHeightChanged: ((CGFloat) -> Void)?
    fileprivate var lastHeight: CGFloat = 0
    @objc public var myContent = 0


  public convenience init() {
    self.init(frame: CGRect.zero)
  }

  override init (frame: CGRect) {
    super.init(frame : frame)
  }

  public required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
  }
    
    deinit {
        self.webView?.scrollView.removeObserver(self, forKeyPath: "contentSize", context: nil)
    }

  open override var intrinsicContentSize: CGSize {
    if let height = self.intrinsicContentHeight {
      return CGSize(width: UIView.noIntrinsicMetric, height: height)
    } else {
      return CGSize.zero
    }
  }

  public func load(markdown: String?, enableImage: Bool = true) {
    guard let markdown = markdown else { return }

    self.webView?.scrollView.removeObserver(self, forKeyPath: "contentSize", context: nil)
    
    let bundle = Bundle(for: MarkdownView.self)

    let htmlURL: URL? =
      bundle.url(forResource: "index",
                 withExtension: "html") ??
      bundle.url(forResource: "index",
                 withExtension: "html",
                 subdirectory: "MarkdownView.bundle")

    if let url = htmlURL {
      let templateRequest = URLRequest(url: url)

      let escapedMarkdown = self.escape(markdown: markdown) ?? ""
      let imageOption = enableImage ? "true" : "false"
      let script = "window.showMarkdown('\(escapedMarkdown)', \(imageOption));"
      let userScript = WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)

      let controller = WKUserContentController()
      controller.addUserScript(userScript)

      let configuration = WKWebViewConfiguration()
      configuration.userContentController = controller

      let wv = WKWebView(frame: self.bounds, configuration: configuration)
      wv.scrollView.isScrollEnabled = self.isScrollEnabled
      wv.translatesAutoresizingMaskIntoConstraints = false
      wv.navigationDelegate = self
      addSubview(wv)
      wv.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
      wv.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
      wv.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
      wv.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
      wv.backgroundColor = self.backgroundColor

      self.webView = wv

      wv.load(templateRequest)
        
        self.webView?.scrollView.addObserver(self, forKeyPath: "contentSize", options: NSKeyValueObservingOptions.new, context: nil)
        
    } else {
      // TODO: raise error
    }
  }

  private func escape(markdown: String) -> String? {
    return markdown.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics)
  }
    

    open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        // 注：该方案的异常问题是：当显示MarkdownView时延迟几秒调用getContentHeight后会同步更新，但如果不调用就不自动更新。
        guard let keyPath = keyPath, keyPath == "contentSize", let webView = self.webView else {
            return
        }
        let height: CGFloat = webView.scrollView.contentSize.height ?? 0
        // 防止滚动一直刷新，出现闪屏
        if abs(height - lastHeight) > 0.000001 {
            self.onHeightChanged?(height)
            lastHeight = height
            print("MarkdownView observeValue of change context, newHeight: \(height)")
        }
    }


}


public extension MarkdownView {

    public func getContentHeight(complete: ((_ height: CGFloat) -> Void)?) -> Void {
        // 该处的问题是：参考WKNavigationDelegate里
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 5.0) {
            //let script: String = "document.getElementById(\'testDiv\').offsetTop"
            //let script = "document.body.scrollHeight;"
            let script = "document.body.offsetHeight;"
            self.webView?.evaluateJavaScript(script) { [weak self] result, error in
                if let _ = error { return }
                if let height = result as? CGFloat {
                    complete?(height)
                    print("MarkdownView getContentHeight \(height)")
                }
            }
        }
    }

}


extension MarkdownView: WKNavigationDelegate {

  public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    // 该处的问题是：
    //  1. 如果该MarkdownView未显示在屏幕上时，获取的高度不正确；
    //  2. 即使显示在屏幕上，也应延迟几秒调用，否则获取的高度也不正确；
    
    // 方法一：js
    //let script = "document.body.scrollHeight;"
    let script = "document.body.offsetHeight;"
    //let script: String = "document.getElementById(\'testDiv\').offsetTop"
    webView.evaluateJavaScript(script) { [weak self] result, error in
      if let _ = error { return }

      if let height = result as? CGFloat {
        self?.onRendered?(height)
        self?.intrinsicContentHeight = height
        print("MarkdownView webView didFinish \(height)")
      }
    }


//    // 方法二: sizeToFit
//    webView.sizeToFit()
//    let height: CGFloat = webView.scrollView.contentSize.height
////    self.onRendered?(height)
////    self.intrinsicContentHeight = height
//    print("MarkdownView webView didFinish \(height)")


//    // 方法三:遍历WKWebView的所有子视图，找到中间的WKContentView,获取到它的frame设定给webView
//    for view in webView.scrollView.subviews {
//        if let view = view as? WKContentView {
//
//        }
//        print(view.description)
//        print(view.bounds)
//    }

    
    // 方法四：给页面底部添加控件，获取其顶部高度，参考方法1的中js，该方法必须在加载内容时注意控件；

  }

  public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

    switch navigationAction.navigationType {
    case .linkActivated:
      if let onTouchLink = onTouchLink, onTouchLink(navigationAction.request) {
        decisionHandler(.allow)
      } else {
        decisionHandler(.cancel)
      }
    default:
      decisionHandler(.allow)
    }

  }

}
