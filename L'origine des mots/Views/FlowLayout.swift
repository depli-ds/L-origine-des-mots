import SwiftUI

struct FlowLayout: Layout {
    let spacing: CGFloat
    
    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions(),
            subviews: subviews,
            spacing: spacing
        )
        return result.bounds
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions(),
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX,
                                     y: bounds.minY + result.frames[index].minY),
                         proposal: ProposedViewSize(result.frames[index].size))
        }
    }
}

struct FlowResult {
    var bounds = CGSize.zero
    var frames: [CGRect] = []
    
    init(in maxSize: CGSize, subviews: LayoutSubviews, spacing: CGFloat) {
        var origin = CGPoint.zero
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        
        for subview in subviews {
            let subviewSize = subview.sizeThatFits(.unspecified)
            
            if origin.x + subviewSize.width > maxSize.width && origin.x > 0 {
                // Move to next line
                origin.x = 0
                origin.y += lineHeight + spacing
                lineHeight = 0
            }
            
            frames.append(CGRect(origin: origin, size: subviewSize))
            
            origin.x += subviewSize.width + spacing
            lineHeight = max(lineHeight, subviewSize.height)
            maxX = max(maxX, origin.x - spacing)
        }
        
        bounds = CGSize(width: maxX, height: origin.y + lineHeight)
    }
} 