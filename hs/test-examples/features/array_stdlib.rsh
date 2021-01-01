'reach 0.1';

export const main =
  Reach.App(
    {},
    [['A', {}]],
    (A) => {
      A.only(() => {
        const a = Array.iota(5);
        assert(a.sum() == 10);
        assert(a.min() == 0);
        assert(a.max() == 4);
        assert(a.count(x => x < 3) == 3);
        assert(Array.any(a, x => x < 2));
        assert(!Array.all(a, x => x < 2));
        assert(a.findIndex(x => x == 2) == Maybe(UInt).Some(2));
        assert(a.indexOf(15) == Maybe(UInt).None());
        assert(Array.and(array(Bool, [true, true])));
        assert(Array.or(array(Bool, [true, false])));
        assert(a.includes(2));
        assert(!a.includes(322));
      });
    });
