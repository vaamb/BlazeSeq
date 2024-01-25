from MojoFastTrim.helpers import slice_tensor, write_to_buff
from memory.unsafe import DTypePointer
from tensor import Tensor
from MojoFastTrim.CONSTS import *

@value
struct FastqRecord(CollectionElement, Sized, Stringable):
    """Struct that represent a single FastaQ record."""

    var SeqHeader: Tensor[DType.int8]
    var SeqStr: Tensor[DType.int8]
    var QuHeader: Tensor[DType.int8]
    var QuStr: Tensor[DType.int8]
    var total_length: Int

    fn __init__(
        inout self,
        SH: Tensor[DType.int8],
        SS: Tensor[DType.int8],
        QH: Tensor[DType.int8],
        QS: Tensor[DType.int8],
    ) raises -> None:
        if SH[0] != read_header:
            print(SH)
            raise Error("Sequence Header is corrput")

        if QH[0] != quality_header:
            print(QH)
            raise Error("Quality Header is corrput")

        if SS.num_elements() != QS.num_elements():
            print(
                "SeqStr_length:",
                SS.num_elements(),
                "QualityStr_Length:",
                QS.num_elements(),
            )
            raise Error("Corrput Lengths")

        self.SeqHeader = SH
        self.QuHeader = QH

        if self.QuHeader.num_elements() > 1:
            if self.QuHeader.num_elements() != self.SeqHeader.num_elements():
                print(QH)
                raise Error("Quality Header is corrupt")

        self.SeqStr = SS
        self.QuStr = QS

        self.total_length = (
            SH.num_elements()
            + SS.num_elements()
            + QH.num_elements()
            + QS.num_elements()
            + 4  # Addition of 4 \n again
        )

    @always_inline
    fn wirte_record(self) -> Tensor[DType.int8]:
        return self.__concat_record()

    @always_inline
    fn _empty_record(inout self):
        let empty = Tensor[DType.int8](0)
        self.SeqStr = empty
        self.SeqHeader = empty
        self.QuStr = empty
        self.QuHeader = empty
        self.total_length = 0

    @always_inline
    fn __concat_record(self) -> Tensor[DType.int8]:
        if self.total_length == 0:
            return Tensor[DType.int8](0)

        var offset = 0
        var t = Tensor[DType.int8](self.total_length)

        write_to_buff(self.SeqHeader, t, offset)
        offset = offset + self.SeqHeader.num_elements() + 1
        t[offset - 1] = new_line

        write_to_buff(self.SeqStr, t, offset)
        offset = offset + self.SeqStr.num_elements() + 1
        t[offset - 1] = new_line

        write_to_buff(self.QuHeader, t, offset)
        offset = offset + self.QuHeader.num_elements() + 1
        t[offset - 1] = new_line

        write_to_buff(self.QuStr, t, offset)
        offset = offset + self.QuStr.num_elements() + 1
        t[offset - 1] = new_line

        return t

    @always_inline
    fn __str__(self) -> String:
        if self.total_length == 0:
            return ""
        var concat = self.__concat_record()
        return String(concat._steal_ptr(), self.total_length)

    @always_inline
    fn __len__(self) -> Int:
        return self.SeqStr.num_elements()




@always_inline
fn trim_record(inout record: FastqRecord, direction: String = "end", quality_threshold: Int = 20):
    """Algorithm for record trimming replicating trimming method implemented by BWA and cutadapt.
    """

    var s: Int8 = 0
    var min_qual: Int8 = 0
    let n = record.QuStr.num_elements()
    var stop: Int = n
    var start: Int = 0
    let i: Int

    ## minimum of Rolling sum algorithm used by Cutadapt and BWA
    # Find trim position in 5' end
    for i in range(n):
        s += record.QuStr[i] - 33 - quality_threshold
        if s > 0:
            break
        if s < min_qual:
            min_qual = s
            start = i + 1

    # Find trim position in 3' end
    min_qual = 0
    s = 0
    for i in range(1, n):
        s += record.QuStr[n - i] - 33 - quality_threshold
        if s > 0:
            break
        if s < min_qual:
            min_qual = s
            stop = stop - 1

    if start >= stop:
        record._empty_record()
        return

    if direction == "end":
        record.SeqStr = slice_tensor[USE_SIMD=USE_SIMD](record.SeqStr, 0, stop)
        record.QuStr = slice_tensor[USE_SIMD=USE_SIMD](record.QuStr, 0, stop)

    if direction == "start":
        record.SeqStr = slice_tensor[USE_SIMD=USE_SIMD](record.SeqStr, start, n)
        record.QuStr = slice_tensor[USE_SIMD=USE_SIMD](record.QuStr, start, n)

    if direction == "both":
        record.SeqStr = slice_tensor[USE_SIMD=USE_SIMD](record.SeqStr, start, stop)
        record.QuStr = slice_tensor[USE_SIMD=USE_SIMD](record.QuStr, start, stop)

    record.total_length = (
        record.SeqHeader.num_elements()
        + record.SeqStr.num_elements()
        + record.QuHeader.num_elements()
        + record.QuStr.num_elements()
        + 4
    )
