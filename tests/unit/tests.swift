@testable import PNG4

extension Test 
{
    static 
    var cases:[(name:String, function:Function)] 
    {
        [
            ("decode-bitstream",            .void(Self.decodeBitstream)),
            ("encode-bitstream",            .void(Self.encodeBitstream)),
            ("match-lz77",                  .void(Self.matchLZ77)),
            ("compress-swift-z",            .int(Self.compressZ(count:),  [5, 15, 100, 200, 2000, 5000])),
            ("filtering",                   .int( Self.filtering(delay:), [1, 2, 3, 4, 5, 6, 7, 8])),
            ("premultiplication-8-bit",     .void(Self.premultiplication8)),
            ("premultiplication-16-bit",    .void(Self.premultiplication16)),
        ]
    }
    static 
    func decodeBitstream() -> Result<Void, Failure> 
    {
        var bits:LZ77.Inflator.In = 
        [
            0b1001_1110,
            0b1111_0110,
            0b0010_0011,
        ]
        guard   bits[ 0] == 0b1111_0110_1001_1110 ,
                bits[ 1] == 0b1_1111_0110_1001_111,
                bits[ 2] == 0b11_1111_0110_1001_11,
                bits[ 3] == 0b011_1111_0110_1001_1,
                bits[ 4] == 0b0011_1111_0110_1001 ,
                bits[ 5] == 0b0_0011_1111_0110_100,
                bits[ 6] == 0b10_0011_1111_0110_10,
                bits[ 7] == 0b010_0011_1111_0110_1,
                bits[ 8] == 0b0010_0011_1111_0110 ,
                bits[ 9] == 0b0_0010_0011_1111_011,
                bits[23] == 0b0000_0000_0000_0000
        else 
        {
            return .failure(.init(message: "incorrect codeword read"))
        }
        guard   bits[0, count:  4, as: Int.self] ==                   0b1110,
                bits[1, count:  4, as: Int.self] ==                 0b1_111,
                bits[1, count:  6, as: Int.self] ==               0b001_111,
                bits[2, count:  6, as: Int.self] ==              0b1001_11,
                bits[2, count: 16, as: Int.self] == 0b11_1111_0110_1001_11
        else
        {
            return .failure(.init(message: "incorrect integer read"))
        }
        
        // test rebase 
        //                       { 0010_0011, 1111_0110, 1001_1110 }
        //                            ^
        //                          b = 20
        // ->
        // { 0001_1000, 1010_1101, 0010_0011 }
        //                            ^
        //                          b = 4
        var b:Int = 20 
        bits.rebase([0b1010_1101, 0b0001_1000], pointer: &b)
        
        guard   bits[b    ] == 0b1000_1010_1101_0010, 
                bits[b + 1] == 0b1_1000_1010_1101_001
        else 
        {
            return .failure(.init(message: "incorrect rebased codeword read"))
        }
        // test rebase 
        //                       { 0001_1000, 1010_1101, 0010_0011 }
        //                                                  ^
        //                                                b = 4
        // { 1111_1100, 0011_1111, 0001_1000, 1010_1101, 0010_0011 }
        bits.rebase([0b0011_1111, 0b1111_1100], pointer: &b)
        
        guard   bits[b    ] == 0b1000_1010_1101_0010, 
                bits[b + 8] == 0b1111_0001_1000_1010
        else 
        {
            return .failure(.init(message: "incorrect rebased codeword read"))
        }
        return .success(())
    }
    
    static 
    func encodeBitstream() -> Result<Void, Failure>
    {
        var bits:LZ77.Deflator.Out = .init(hint: 4) 
        
        bits.append(0b11, count: 2)
        bits.append(0b01_10, count: 4)
        
        bits.append(0b0110, count: 0)
        
        bits.append(0b1_1111_11, count: 7)
        bits.append(0b1010_1010_1010_101, count: 15)
        bits.append(0b000, count: 3)
        bits.append(0b0_1101_1, count: 6)
        bits.append(0b1_0000_0000_111, count: 12)
        
        var encoded:[UInt8] = []
        while let chunk:[UInt8] = bits.pop() 
        {
            encoded.append(contentsOf: chunk)
        }
        encoded.append(contentsOf: bits.pull())
        
        guard encoded == 
        [
            0b1101_1011,
            0b1011_1111, 
            0b1010_1010, 
            0b1000_1010,
            0b1110_1101,
            0b0000_0000, 
            0b0000_0001
        ]
        else 
        {
            return .failure(.init(message: "incorrect codeword write"))
        }
        return .success(())
    }
    
    static 
    func matchLZ77() -> Result<Void, Failure>
    {
        let segments:[[UInt8]] = 
        [
            [1, 2, 3, 3, 1, 2, 3, 3, 1, 2, 3, 1, 2, 2, 2, 2, 2, 2, 0, 1, 2], 
            [2, 2, 2, 2, 0, 1, 2, 2, 0, 0, 0, 0, 2, 3, 2, 1, 2, 3, 3, 1, 5], 
            [1, 1, 3, 3, 1, 2, 3, 1, 2, 4, 4, 2, 1]
        ]
        var input:LZ77.Deflator.In      = .init()
        var window:LZ77.Deflator.Window = .init(exponent: 4)
        var output:[[UInt8]]            = []
        for (s, segment):(Int, [UInt8]) in segments.enumerated()
        {
            input.enqueue(contentsOf: segment)
            
            while input.count > (s == segments.count - 1 ? 0 : 10)
            {
                if let match:(length:Int, distance:Int) = window.match(input) 
                {
                    var run:[UInt8] = []
                    for _:Int in 0 ..< match.length 
                    {
                        let literal:UInt8 = input.dequeue()
                        run.append(literal)
                        window.register(literal)
                    }
                    output.append(run)
                }
                else 
                {
                    let literal:UInt8 = input.dequeue()
                    window.register(literal)
                    output.append([literal])
                }
            }
        }
        guard output == 
        [
            [1], 
            [2], 
            [3], 
            [3], 
            [1, 2, 3, 3, 1, 2, 3], 
            [1], 
            [2], [2], [2], [2], [2], [2], 
            [0], 
            [1, 2, 2, 2, 2, 2], 
            [0], 
            [1], 
            [2], [2], 
            [0], [0], [0], [0], 
            [2], 
            [3], 
            [2], 
            [1], 
            [2], 
            [3], [3], 
            [1], 
            [5], 
            [1], [1], 
            [3], [3], 
            [1], 
            [2], 
            [3], 
            [1], 
            [2], 
            [4], [4], 
            [2], 
            [1]
        ] 
        else 
        {
            print(output)
            return .failure(.init(message: "compressed lz77 tokens do not match expected output"))
        }

        return .success(())
    }
    
    static 
    func compressZ(count:Int) -> Result<Void, Failure> 
    {
        let input:[UInt8] = (0 ..< count).map{ _ in .random(in: .min ... .max) }
        var deflator:LZ77.Deflator = .init(exponent: 8, hint: 16)
        deflator.push(input, last: true)
        var compressed:[UInt8] = []
        while true 
        {
            let part:[UInt8] = deflator.pull() 
            guard !part.isEmpty 
            else 
            {
                break
            }
            compressed.append(contentsOf: part)
        }
        
        var inflator:LZ77.Inflator = .init()
        do 
        {
            try inflator.push(compressed)
        }
        catch let error 
        {
            return .failure(.init(message: "\(error)"))
        }
        
        let output:[UInt8] = inflator.pull()
        guard input == output 
        else 
        {
            return .failure(.init(message: "decompressor output does not match compressor input"))
        }
        return .success(())
    }
    
    static 
    func filtering(delay:Int) -> Result<Void, Failure> 
    {
        let size:(x:Int, y:Int) = (24, 16)
        let original:[[UInt8]] = (0 ..< size.y).map 
        {
            _ in [0] + (0 ..< size.x).map{ _ in UInt8.random(in: .min ... .max) }
        }
        
        let filtered:[[UInt8]] = .init(unsafeUninitializedCapacity: size.y) 
        {
            $1 = $0.count
            guard let base:UnsafeMutablePointer<[UInt8]> = $0.baseAddress 
            else 
            {
                return 
            }
            
            var last:[UInt8] = .init(repeating: 0, count: size.x + 1)
            for (i, line):(Int, [UInt8]) in zip($0.indices, original)
            {
                (base + i).initialize(to: PNG.Encoder.filter(line, last: last, delay: delay))
                last = line 
            }
        }
        
        let unfiltered:[[UInt8]] = .init(unsafeUninitializedCapacity: size.y) 
        {
            $1 = $0.count
            guard let base:UnsafeMutablePointer<[UInt8]> = $0.baseAddress 
            else 
            {
                return 
            }
            
            var last:[UInt8] = .init(repeating: 0, count: size.x + 1)
            for (i, line):(Int, [UInt8]) in zip($0.indices, filtered)
            {
                var line:[UInt8] = line
                PNG.Decoder.defilter(&line, last: last, delay: delay)
                last  = line 
                
                line[line.startIndex] = 0
                (base + i).initialize(to: line)
            }
        }
        
        for (a, b):([UInt8], [UInt8]) in zip(original, unfiltered) 
        {
            guard a == b 
            else 
            {
                return .failure(.init(message: "original and filter-cycled scanlines do not match"))
            }
        }
        return .success(())
    }
    
    static 
    func premultiplication8() -> Result<Void, Failure>
    {
        Self.premultiplication(for: UInt8.self, over: (.min ... .max, .min ... .max))
    }
    // exhaustive 16-bit premultiplication tests take way too long to run, so we
    // sample a select subset of the input space 
    static 
    func premultiplication16() -> Result<Void, Failure>
    {
        Self.premultiplication(for: UInt16.self, over: 
        (
            (0 ..< 512).map{ _ in .random(in: .min ... .max) },
            (0 ..< 512).map{ _ in .random(in: .min ... .max) }
        ))
    }
    static 
    func premultiplication<T, C>(for _:T.Type, over:(color:C, alpha:C)) -> Result<Void, Failure>
        where   T:FixedWidthInteger & UnsignedInteger, 
                C:Collection, C.Element == T
    {
        for color:T in over.color 
        {
            for alpha:T in over.alpha 
            {
                let direct:PNG.RGBA<T>        = .init(color, alpha),
                    premultiplied:PNG.RGBA<T> = direct.premultiplied

                let unquantized:Double  = (.init(alpha) * .init(color) / .init(T.max)),
                    quantized:T         = .init(unquantized)

                // the order is important here,, the short circuiting protects us from
                // overflow when `quantized` == 255
                guard premultiplied.r == quantized || premultiplied.r == quantized + 1
                else
                {
                    return .failure(.init(message: "premultiplication of rgba\(T.bitWidth)(\(direct.r), \(direct.g), \(direct.b), \(direct.a)) returned (\(premultiplied.r), \(premultiplied.g), \(premultiplied.b), \(premultiplied.a)), expected (\(unquantized), \(unquantized), \(unquantized), \(alpha))"))
                }
            }
        }

        return .success(())
    }
}
