
from fastq_record import FastqRecord
from helpers import IntableString 


struct FastqParser:

    var _file_handle: FileHandle
    var _out_path: String

    fn __init__(inout self, path: String) raises -> None:

        self._file_handle = open(path, "r")
        let in_path = Path(path)
        let suffix = in_path.suffix()
        self._out_path = path.replace(suffix, "")+"_out"+suffix  

    fn parse_records(inout self,
     chunk: Int, 
     infer_quality: Bool = True, 
     trim: Bool = True, 
     min_quality: Int = 20, 
     direction: String = "end") raises -> Int:


        var count: Int = 0
        var bases: Int = 0
        var qu: Int = 0
        var pos: Int = 0
        var record: FastqRecord


        if not self._header_parser():
            return 0
        let out = open(self._out_path, "w")

        while True:
            var reads_vec = self._read_lines_chunk(chunk, pos)
            pos = int(IntableString(reads_vec.pop_back()))

            if len(reads_vec) < 2:
                break

            var i = 0
            while i  < len(reads_vec):
                try:
                    record = FastqRecord(reads_vec[i],
                    reads_vec[i+1],
                    reads_vec[i+2],
                    reads_vec[i+3],
                    )

                    record.trim_record()
                    _ = record.wirte_record()

                    count = count + 1
                    bases = bases + len(record)
                    qu = qu + len(record)
                except:
                    pass
                i = i + 4
                    


        print(String("number of bases is: ")+bases)
        print(String("number of quality strings is: ")+qu)
        
        return count


    fn _header_parser(self) raises -> Bool:
        let header: String = self._file_handle.read(1)
        _ = self._file_handle.seek(0)
        print("header verified")
        if header != "@":
            raise Error("Fastq file should start with valid header '@'")
        return True


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


fn main() raises:
    import time 
    from math import math

    let KB = 1024
    let MB = 1024*KB

    let t1 = time.now()
    var parser = FastqParser("data/SRR16012060.fastq")
    let num = parser.parse_records(chunk = 100*MB, min_quality = 28)
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