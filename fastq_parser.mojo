
#TODO: Implement a quality trimming algorithm as by Cutadapt.
#TODO: Implement 

@value
struct FastqRecord(CollectionElement, Stringable, Sized):
    """Struct that represent a single FastaQ record."""
    var SeqHeader: String
    var SeqStr: String
    var QuHeader: String
    var QuStr: String
    var QuInt: DynamicVector[Int8]

    fn __init__(inout self, SH: String, SS: String, QH: String, QS: String) raises -> None:

        if SH[0] != "@":
            pass
            #print("Sequence Header is corrput")
            #print(SH)

        if QH[0] != "+":
            print("Quality Header is corrput")

        self.SeqHeader = SH[1:]
        self.QuHeader = QH[1:]

        if len(self.QuHeader) > 0:
            if self.QuHeader != self.SeqHeader:
                print("Quality Header is corrupt")
                pass

        self.SeqStr = SS
        self.QuStr = QS
        self.QuInt = DynamicVector[Int8](capacity =len(SS))
        self.infer_qualities()

    fn infer_qualities(inout self):
        for i in range(len(self.SeqStr)):
            self.QuInt.push_back(ord(self.QuStr[i]) - 33)

    fn trim_record(inout self, quality_threshold: Int = 20):
        pass

    fn wirte_record(self) -> String:
        var s = String()
        s += "@"+self.SeqHeader +"\n"
        s += self.SeqStr + "\n"
        s += "+"+self.QuHeader+"\n"
        s += self.QuStr

        print(s)

        return s


    fn __str__(self) -> String:

        var str_repr = String()
        str_repr += "Record:"
        str_repr += self.SeqHeader
        str_repr += "\nSeq:"
        str_repr += self.SeqStr
        str_repr += " \n"
        str_repr += "Quality: "
        str_repr += self.QuStr
        str_repr += "\nInfered Quality: "

        for i in range(len(self.QuInt)):
            str_repr += self.QuInt[i]
            str_repr += "_"

        return str_repr

    fn __len__(self) -> Int:
        return len(self.SeqStr)
 

struct FastqCollection(Stringable, Sized):

    """
    Struct represents a collecion of FastqRecord. 
    it is backed by a dynamic vector and can be passed around or multi-core processing.
    it provides convience methods for starting trimming and writing of the contained records.
    """

    var data: DynamicVector[FastqRecord]

    fn __init__(inout self):
        self.data = DynamicVector[FastqRecord]()

    fn write_collection(self, borrowed file_handle: FileHandle) raises -> None:
        pass

    fn __str__(self) -> String:
        return ""

    fn __len__(self) -> Int:
        return 1



struct FastqParser:

    var _file_handle: FileHandle
    var _parsed_records: DynamicVector[FastqRecord]

    fn __init__(inout self, owned file_handle: FileHandle) raises -> None:

        self._file_handle = file_handle^
        self._parsed_records = DynamicVector[FastqRecord]()

    fn parse_records(inout self, chunk: Int) raises -> Int:
        var count: Int = 0
        var bases: Int = 0
        var pos: Int = 0
        let record: FastqRecord
        self._header_parser()

        while True:
            
            var reads_vec = self._read_lines_chunk(chunk, pos)
            pos = int(intable_string(reads_vec.pop_back()))

            if len(reads_vec) < 2:
                break

            var i = 0

            while i  < len(reads_vec):
                try:
                    record = FastqRecord(reads_vec[i],reads_vec[i+1], reads_vec[i+2], reads_vec[i+3])
                    #self._parsed_records.append(record)
                    count = count +1
                    bases = bases + len(reads_vec[i])

                except:
                    pass

                i = i + 4
                
        #print(String("The number of parser records is ")+len(self._parsed_records))
        #return len(self._parsed_records)
        print(String("number of bases is: ")+bases)
        return count


    fn _header_parser(self) raises -> None:
        let header: String = self._file_handle.read(1)
        _ = self._file_handle.seek(0)
        print("header verified")
        if header != "@":
            raise Error("Fastq file should start with valid header '@'")
        return None


    fn _read_lines_chunk(self, chunk_size: Int = -1,  current_pos: UInt64 = 0) raises -> DynamicVector[String]:
        
        let s = self._file_handle.read(chunk_size)
        var vec = s.split("\n")
        let vec_n = len(vec)

        if vec_n < 4:
            let pos = self._file_handle.seek(current_pos)
            vec.push_back(pos)
            return vec

        var rem = vec_n % 4
        var retreat = 0    

        if rem == 0: # The whole last record is untrustworthy remove the last 4 elements.
            rem = 4

        for i in range(rem):
            retreat = retreat + len(vec[vec_n - (i+1)])
            _ = vec.pop_back()

        let pos = self._file_handle.seek(current_pos+chunk_size-retreat)
        vec.push_back(pos)
        return vec



@value
struct intable_string(Intable, Stringable):

    var data: String

    fn __str__(self) -> String:
        return self.data
    
    fn __int__(self) -> Int:
        let data_n = len(self.data)
        var n: Int = 0
        for i in range(0, data_n):
            let chr: Int = ord(self.data[i]) -48
            n = n + chr * (10**(data_n-(i+1)))
        return n






fn main() raises:
    import time 
    from math import math

    let f = open("102_20.fq", "r")
    var parser = FastqParser(f^)
    
    let t1 = time.now()
    let num = parser.parse_records(chunk= 1024*1024*100)
    print(String("number of reads is: ")+num)
    let t2 = time.now()
    let t_sec = ((t2-t1) / 1e9)
    let s_per_r = t_sec/num
    print(
        String(t_sec)+
        String(" s spend in parsing euqaling ")+
        String((s_per_r) * 1e6)+
        String(" microseconds/read or ")+
        String(math.round[DType.float32, 1](1/s_per_r))+
        String(" reads/second")
        )
    #print(parser._parsed_records[len(parser._parsed_records)-1])



