include Formule

module BDT = functor(Var : Variable) -> struct

    module F = Formule(Var)

    let build (formule: F.t) =
        let i = ref 0 in
        let rec aux k valuation = function
            | [] -> k (Leaf(F.eval valuation formule))
            | t::q ->
                begin
                    (* print_string ((string_of_int !i) ^ ","); *)
                    i := !i + 1;
                    let k0 a b =
                        k (Node(t, a, b))
                    in
                    let k1 a =
                        Valuation.setValue valuation t false;
                        aux (k0 a) valuation q
                    in
                    Valuation.setValue valuation t true;
                    aux k1 valuation q
                end
        in
        aux (fun x -> x) (Valuation.empty ()) (F.setVar formule)
   
    let isLeaf = function
        | Leaf(_) -> true
        | _ -> false
    
    let rec reduce tree =
        match tree with
        | Leaf(_) -> tree
        | Node(_, Leaf(b1), Leaf(b2)) -> if b1 == b2 then Leaf(b1) else tree
        | Node(v, t1, t2) ->
            begin
                let a = reduce t1 in
                let b = reduce t2 in
                if (isLeaf a && isLeaf b) then
                    reduce (Node(v, a, b))
                else
                    Node(v, a, b)
            end

    let rec toString tree = 
      match tree with
      |Leaf(true) -> "L(T)"
      |Leaf(false) -> "L(F)"
      |Node(x,l,r) -> "N(" ^x ^ "," ^ (toString l) ^ "," ^ (toString r) ^ ")"
    
end

module BDD = functor(Var: Variable) -> struct

    module F = Formule(Var)
    module B = BDT(Var)
  
    let getID = function
    | False -> 0
    | True -> 1
    | ANode(x,_,_,_) -> x
  
    let equalBDD bdd1 bdd2 = (getID bdd1) = (getID bdd2)

    let bij x y =
        (x+y)*(x+y+1)/2  + x
    
    module H = struct
        type t = Var.t*int*int
        let equal (v1, g1, d1) (v2, g2, d2) =
            v1 = v2 && g1 = g2 && d1 = d2
        let hash (v, g, d) =
            Hashtbl.hash (v,g,d)
    end
  
  module HBDD = Hashtbl.Make(H)
    
  let currID = ref 2
  let nodeSet  = HBDD.create 100
    
    
  let makeNode v g d =
    let idg = getID g in
    let idd = getID d in
    if idg = idd
    then g
    else
      try
        HBDD.find nodeSet (v, idg, idd)
      with Not_found ->
        let newID = !currID
        in currID := newID + 1;
        let newNode = ANode(newID,v,g,d)
        in HBDD.add nodeSet (v, idg, idd) newNode;
        newNode

          
          
  module H2 = struct
    type t = int * int
    let equal (a1,b1) (a2,b2) =
      a1 = a2 && b1 = b2
    let hash (a,b) = Hashtbl.hash (a, b)
  end
    
  module HPairBDD = Hashtbl.Make(H2) 

    let notContainer =  Hashtbl.create 5000
      
    let rec notBDD bdd =
      match bdd with
      | False -> True
      | True -> False
      | ANode(id, v, g, d) ->
        try
          Hashtbl.find notContainer id
        with Not_found ->
          let newNode = makeNode v (notBDD g)  (notBDD d)
          in Hashtbl.add notContainer id newNode;
          newNode
            
    let andContainer = HPairBDD.create 5000
      
    let rec andBDD bdd1 bdd2 =
      match bdd1, bdd2 with
      |True, _ -> bdd2
      |False, _ -> False
      |_, True -> bdd1
      |_, False -> False
      |ANode(id1, v1, g1, d1), ANode(id2, v2, g2, d2) ->
         if id1 = id2
         then
           bdd1
         else
           let key = if id1 < id2 then (id1, id2) else (id2, id1)
           in try HPairBDD.find andContainer key
               with Not_found ->
                 let newNode =
                   if v1 = v2
                   then
                     makeNode v1 (andBDD g1 g2) (andBDD d1 d2)
                   else if v1 < v2
                   then
                     makeNode v1 (andBDD g1 bdd2) (andBDD d1 bdd2)
                   else
                     makeNode v2 (andBDD bdd1 g2) (andBDD bdd1 d2)
                 in HPairBDD.add andContainer key newNode;
                 newNode

    let orContainer = HPairBDD.create 5000
      
    let rec orBDD bdd1 bdd2 =
      match bdd1, bdd2 with
      |True, _ -> True
      |False, _ -> bdd2
      |_, True -> True
      |_, False -> bdd1
      |ANode(id1, v1, g1, d1), ANode(id2, v2, g2, d2) ->
         if id1 = id2
         then
           bdd1
         else
           let key = if id1 < id2 then (id1, id2) else (id2, id1)
           in try HPairBDD.find orContainer key 
               with Not_found ->
                 let newNode =
                   if v1 = v2
                   then
                     makeNode v1 (orBDD g1 g2) (orBDD d1 d2)
                   else if v1 < v2
                   then
                     makeNode v1 (orBDD g1 bdd2) (orBDD d1 bdd2)
                   else
                     makeNode v2 (orBDD bdd1 g2) (orBDD bdd1 d2)
                 in HPairBDD.add orContainer (id1, id2) newNode;
                 newNode
                   
    let implBDD bdd1 bdd2 =
      orBDD (notBDD bdd1) bdd2
        
    let equiBDD bdd1 bdd2 =
      orBDD (andBDD bdd1 bdd2) (andBDD (notBDD bdd1) (notBDD bdd2)) 
        
        
    let fromBDT tree =
      let rec help x =
        match x with
        |Leaf(true) -> True
        |Leaf(false) -> False
        |Node(var, a, b) ->
           let g = help a
           in let d = help b
              in makeNode var g d
      in help tree
        

    let rec evaluate valuation = function
      | True -> true
      | False -> false
      | ANode(id, var, t, f) ->
        if Valuation.getValue valuation var then
          evaluate valuation t
        else
          evaluate valuation f
            

    let rec isCombined f = function
      | True -> true
      | False -> false
      | ANode(_, _, a, b) -> f (isCombined f a) (isCombined f b)
                               

    let isSatisfiable bdd = isCombined (fun x y -> x || y) bdd
    let isValid bdd = isCombined (fun x y -> x && y) bdd

    let rec satisfact = function
      | True -> (true, [])
      | False -> (false, [])
      | ANode(_, var, a, b) -> let (b1, l1) = satisfact a in
        if b1 then (true, (var, true)::l1)
        else let (b2, l2) = satisfact b in (b2, (var, false)::l2)

    let rec print_satisfact = function
      | (_, []) -> ()
      | (false,q) -> ()
      | (true, ((v,b)::a)) -> print_string (Var.toString v); if b then print_string " @f\n" else print_string " @t\n"; print_satisfact (true, a) 

    let create formule = fromBDT(B.reduce (B.build formule))

    let print bdd =
        let getValue = function
            | True ->  "@t"
            | False -> "@f"
            | ANode(id, _, _, _) -> string_of_int id
          in
          let set = ref IntSet.empty in
          let rec aux node set =
            match node with
            | True -> ()
            | False -> ()
            | ANode(id, var, a, b) ->
              begin
                if not (IntSet.mem id (!set)) then
                  begin
                    set := IntSet.add id (!set);
                    let s = (string_of_int id) ^ " " ^ Var.toString var ^ " " ^ (getValue a) ^ " " ^ (getValue b) in
                    print_string (s ^ "\n");
                    aux a set;
                    aux b set;
                  end
              end
      in
      aux bdd set
        
            
    let rec createBDD formule =
    match formule with
      |Var v         -> makeNode v False True
      |True          -> True
      |False         -> False
      |Not e         -> notBDD (createBDD e)
      |And (e1, e2)  -> andBDD (createBDD  e1)  (createBDD e2)
      |Or (e1, e2)   -> orBDD (createBDD e1)  (createBDD e2)
      |Imp  (e1, e2) -> implBDD (createBDD e1) (createBDD e2)
      |Equi (e1, e2) -> equiBDD (createBDD e1) (createBDD e2)

end

module IntBDD = BDD(IntVar)
module StringBDD = BDD(StringVar)
module StringBDT = BDT(StringVar)

